import SwiftUI
import WatchKit

/// Squad comms on the wrist.
///
/// This is the closest match to what the app is actually for. The whole point
/// is training with your phone in a pocket and never touching it — but muting
/// yourself is the one thing you genuinely need mid-set, when you're breathing
/// hard, counting, or somebody walks up to talk to you in the real world.
/// Fishing a phone out to do that defeats the entire premise.
///
/// So the watch does exactly two things: shows who is talking, and mutes you.
/// Nothing else. Anything more and it becomes a thing you look at.
@main
struct SquadCommsWatchApp: App {
    @StateObject private var link = WatchLink()

    var body: some Scene {
        WindowGroup {
            WristView()
                .environmentObject(link)
        }
    }
}

struct WristView: View {
    @EnvironmentObject private var link: WatchLink

    var body: some View {
        VStack(spacing: 10) {
            if !link.onLine {
                Text("No line open")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                // Who has the floor. One line, readable at a glance with a
                // barbell in your hands.
                Text(link.talking.isEmpty ? "Nobody talking"
                                          : link.talking.joined(separator: ", "))
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(link.talking.isEmpty ? .secondary : .primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                Button {
                    link.toggleMute()
                    WKInterfaceDevice.current().play(.click)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: link.muted ? "mic.slash.fill" : "mic.fill")
                            .font(.system(size: 30))
                        Text(link.muted ? "Muted" : "Live")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(link.muted ? Color.gray.opacity(0.25)
                                         : Color(red: 0.922, green: 0.796, blue: 0.294))
                )
                .foregroundStyle(link.muted ? .white : .black)
            }
        }
        .padding(.horizontal, 8)
    }
}
