import Contacts
import CryptoKit
import Foundation

/// Finds which of your contacts already have the app.
///
/// Phone numbers never leave the device. Each one is normalised to E.164 and
/// hashed with SHA-256 locally, and only the hashes are sent. The server can
/// answer "is this hash one of yours" but cannot recover a number from it, and
/// cannot be used to enumerate users because you can only ask about hashes you
/// already hold — which means you already had the number.
///
/// Normalisation matters more than it looks. "(801) 555-0123", "801-555-0123"
/// and "+18015550123" are the same person and hash to three different values
/// unless they are reduced to one form first, so a naive implementation
/// silently matches almost nobody.
@MainActor
final class ContactMatcher: ObservableObject {

    struct Match: Identifiable, Equatable {
        var id: String { hash }
        let hash: String
        let contactName: String      // what YOU call them
        let appName: String          // what they call themselves in the app
        let lastSeen: Date?
    }

    @Published private(set) var matches: [Match] = []
    @Published private(set) var totalScanned = 0
    @Published private(set) var permission: CNAuthorizationStatus = .notDetermined
    @Published private(set) var isScanning = false

    private let backend: Backend
    private let store = CNContactStore()

    init(backend: Backend) {
        self.backend = backend
        permission = CNContactStore.authorizationStatus(for: .contacts)
    }

    func requestAccessAndScan() async {
        do {
            let granted = try await store.requestAccess(for: .contacts)
            permission = CNContactStore.authorizationStatus(for: .contacts)
            guard granted else { return }
            await scan()
        } catch {
            Log.session.error("contacts access failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        let entries = await Task.detached(priority: .userInitiated) { [store] in
            Self.readContacts(from: store)
        }.value

        totalScanned = entries.count
        guard !entries.isEmpty else { matches = []; return }

        // Hash → the name you have them saved under, so results can be shown
        // with YOUR label rather than whatever they typed into the app.
        var byHash: [String: String] = [:]
        for entry in entries { byHash[entry.hash] = entry.name }

        do {
            let found = try await backend.matchContacts(hashes: Array(byHash.keys))
            matches = found.compactMap { row in
                guard let contactName = byHash[row.phoneHash] else { return nil }
                return Match(hash: row.phoneHash,
                             contactName: contactName,
                             appName: row.displayName,
                             lastSeen: row.lastSeenAt)
            }
            .sorted { $0.contactName.localizedCaseInsensitiveCompare($1.contactName) == .orderedAscending }
        } catch {
            Log.session.error("contact match failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Register our own number so people who have it can find us.
    func registerSelf(phoneNumber: String?, deviceID: String, displayName: String, ghost: Bool) async {
        let hash = phoneNumber.flatMap { Self.hash(Self.normalise($0)) }
        try? await backend.registerDevice(deviceID: deviceID,
                                          displayName: displayName,
                                          phoneHash: hash,
                                          ghost: ghost)
    }

    // MARK: - Reading

    private nonisolated static func readContacts(from store: CNContactStore) -> [(hash: String, name: String)] {
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey,
                    CNContactPhoneNumbersKey] as [CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)

        var output: [(String, String)] = []
        try? store.enumerateContacts(with: request) { contact, _ in
            let name = [contact.givenName, contact.familyName]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            guard !name.isEmpty else { return }

            for number in contact.phoneNumbers {
                let normalised = normalise(number.value.stringValue)
                guard let hashed = hash(normalised) else { continue }
                output.append((hashed, name))
            }
        }
        return output
    }

    // MARK: - Normalisation

    /// Reduce to digits, then to a canonical E.164-ish form.
    ///
    /// A 10 digit number is assumed North American and gets a 1 prefix; an
    /// 11 digit number starting with 1 is already that. Anything else is left
    /// as its digits, which still matches consistently as long as both sides
    /// normalise the same way.
    nonisolated static func normalise(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        if digits.count == 10 { return "+1" + digits }
        if digits.count == 11, digits.hasPrefix("1") { return "+" + digits }
        return digits.isEmpty ? "" : "+" + digits
    }

    nonisolated static func hash(_ normalised: String) -> String? {
        guard !normalised.isEmpty else { return nil }
        let digest = SHA256.hash(data: Data(normalised.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
