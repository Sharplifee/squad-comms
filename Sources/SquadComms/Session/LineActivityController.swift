import ActivityKit
import Foundation

/// Runs the lock-screen Live Activity for an open line.
///
/// The north star is two people training for an hour without touching their
/// phones. The thing that breaks it is needing to mute — you have to wake the
/// phone, unlock it, find the app. A Live Activity puts the line state and a
/// mute button on the lock screen and in the Dynamic Island, so it costs a
/// glance and one tap.
@MainActor
final class LineActivityController {
    static let shared = LineActivityController()
    private init() {}

    private var activity: Activity<LineActivityAttributes>?

    func start(squadName: String, code: String, memberCount: Int) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard activity == nil else { return }

        let attributes = LineActivityAttributes(squadName: squadName, code: code)
        let state = LineActivityAttributes.ContentState(
            speaker: nil, selfMuted: false,
            memberCount: memberCount, startedAt: Date()
        )

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil)
            )
        } catch {
            // A Live Activity failing to start must never affect the line —
            // it is a convenience layer over something already working.
            Log.session.error("live activity failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func update(speaker: String?, selfMuted: Bool, memberCount: Int, startedAt: Date) {
        guard let activity else { return }
        let state = LineActivityAttributes.ContentState(
            speaker: speaker, selfMuted: selfMuted,
            memberCount: memberCount, startedAt: startedAt
        )
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
