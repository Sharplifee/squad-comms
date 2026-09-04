import SwiftUI
import Contacts
import UIKit

/// Who you already know that has the app.
///
/// The point is to remove the step where you have to ask someone whether they
/// have it. If they do, they show up here with your name for them and you send
/// them your code in one tap.
struct ContactsView: View {
    @EnvironmentObject private var session: SessionManager
    @StateObject private var matcher: ContactMatcher
    @State private var query = ""

    private var filtered: [ContactMatcher.Match] {
        guard !query.isEmpty else { return matcher.matches }
        return matcher.matches.filter {
            $0.contactName.localizedCaseInsensitiveContains(query)
            || $0.appName.localizedCaseInsensitiveContains(query)
        }
    }

    init(backend: Backend) {
        _matcher = StateObject(wrappedValue: ContactMatcher(backend: backend))
    }

    var body: some View {
        NavigationStack {
            List {
                // .limited is iOS 18+, so it cannot be matched by name here.
                // Anything that is neither denied nor undetermined means we
                // have some level of access and should just try to read.
                switch matcher.permission {
                case .denied, .restricted:  deniedSection
                case .notDetermined:        askSection
                default:
                    matchedSection
                    privacySection
                }
            }
            .navigationTitle("Contacts")
            // Worth having even at a handful of matches: this list grows with
            // your address book, not with your squad.
            .searchable(text: $query, prompt: "Search contacts")
            .refreshable { await matcher.scan() }
            .task {
                // Publish our own hash first. Matching is symmetric: if we
                // never register, everybody who has our number searches and
                // finds nothing, and the feature looks broken from their side
                // rather than ours.
                await matcher.registerSelf(
                    phoneNumber: nil,
                    deviceID: UIDevice.current.identifierForVendor?.uuidString ?? "unknown",
                    displayName: PreferencesStore.shared.current.displayName,
                    ghost: PreferencesStore.shared.current.visibility == .hidden
                )
                switch matcher.permission {
                case .denied, .restricted, .notDetermined: break
                default: await matcher.scan()
                }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var matchedSection: some View {
        if matcher.isScanning && matcher.matches.isEmpty {
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Checking your contacts…")
                        .foregroundStyle(Theme.textDim)
                }
            }
        } else if matcher.matches.isEmpty {
            Section {
                ContentUnavailableView(
                    "Nobody yet",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("None of your \(matcher.totalScanned) contacts have Squadstream. Send someone your code and they'll show up here once they're on.")
                )
                .listRowBackground(Color.clear)
            }
        } else {
            Section {
                if filtered.isEmpty {
                    Text("No match for \"\(query)\"")
                        .foregroundStyle(Theme.textDim)
                } else {
                    ForEach(filtered) { match in
                        ContactRowView(match: match, code: session.squad?.joinCode)
                    }
                }
            } header: {
                Text("^[\(matcher.matches.count) contact](inflect: true) already on")
            }
        }
    }

    private var privacySection: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your contacts stay on your phone")
                        .font(.subheadline)
                    Text("Numbers are scrambled on the device before anything is sent, and only the scrambled version is compared. Nothing readable ever leaves.")
                        .font(.caption)
                        .foregroundStyle(Theme.textDim)
                }
            } icon: {
                Image(systemName: "lock.shield").foregroundStyle(Theme.live)
            }
        }
    }

    private var askSection: some View {
        Section {
            ContentUnavailableView {
                Label("Find your squad", systemImage: "person.2.badge.key")
            } description: {
                Text("See which of your contacts already have Squadstream. Numbers are scrambled on your phone first — nothing readable is sent.")
            } actions: {
                Button("Check my contacts") {
                    Task { await matcher.requestAccessAndScan() }
                }
                .buttonStyle(.borderedProminent)
            }
            .listRowBackground(Color.clear)
        }
    }

    private var deniedSection: some View {
        Section {
            ContentUnavailableView {
                Label("Contacts are off", systemImage: "lock")
            } description: {
                Text("Turn on Contacts for Squadstream in Settings to see who already has it.")
            } actions: {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
            }
            .listRowBackground(Color.clear)
        }
    }
}

private struct ContactRowView: View {
    let match: ContactMatcher.Match
    let code: String?

    var body: some View {
        HStack(spacing: 12) {
            Text(initials)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textDim)
                .frame(width: 38, height: 38)
                .background(Theme.surfaceAlt, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(match.contactName)
                // They may have typed a different name into the app. Showing it
                // avoids the confusion of a code arriving from a name you do
                // not recognise on the other end.
                if match.appName != match.contactName {
                    Text("Goes by \(match.appName)")
                        .font(.caption)
                        .foregroundStyle(Theme.textDim)
                }
            }

            Spacer()

            if let code {
                ShareLink(item: "Join my squad on Squadstream — code \(code)") {
                    Text("Invite").font(.subheadline)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }

    private var initials: String {
        let parts = match.contactName.split(separator: " ")
        return String(parts.prefix(2).compactMap(\.first)).uppercased()
    }
}
