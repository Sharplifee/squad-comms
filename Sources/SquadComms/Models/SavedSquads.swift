import Foundation

/// The squads you keep going back to.
///
/// The brief calls this the biggest win available, and it is: the same two
/// people were re-sharing a fresh code every single day for a line they open
/// every single day. A saved squad is just a name and a code you chose, so
/// reopening it is one tap and the other person's saved entry still points at
/// the same code.
///
/// This works precisely because codes are user-chosen. A generated code could
/// never be saved meaningfully — it would be different tomorrow.
struct SavedSquad: Codable, Identifiable, Equatable {
    var id: String { code }
    let code: String
    var name: String
    var lastOpened: Date
    /// Who was on it last time, for recognising which squad is which.
    var lastMembers: [String]

    var subtitle: String {
        lastMembers.isEmpty ? "Just you last time"
                            : lastMembers.joined(separator: ", ")
    }
}

@MainActor
final class SavedSquadStore: ObservableObject {
    static let shared = SavedSquadStore()

    @Published private(set) var squads: [SavedSquad] = []

    private let key = "squadcomms.savedSquads"

    private init() { load() }

    func remember(code: String, name: String, members: [String]) {
        // A name you typed outranks the one the session reports. Without this,
        // reconnecting silently reverts every rename.
        let existingName = squads.first { $0.code == code }?.name
        let name = existingName ?? name
        var next = squads.filter { $0.code != code }
        next.insert(SavedSquad(code: code, name: name,
                               lastOpened: Date(), lastMembers: members), at: 0)
        // Six is enough to cover the squads somebody actually has without the
        // list becoming something to scroll.
        squads = Array(next.prefix(6))
        save()
    }

    func forget(_ squad: SavedSquad) {
        squads.removeAll { $0.code == squad.code }
        save()
    }

    func rename(_ squad: SavedSquad, to name: String) {
        guard let index = squads.firstIndex(where: { $0.code == squad.code }) else { return }
        squads[index].name = name
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SavedSquad].self, from: data)
        else { return }
        squads = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(squads) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
