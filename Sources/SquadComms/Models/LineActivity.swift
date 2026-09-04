import ActivityKit
import Foundation

/// The shape of the Live Activity shared between the app and the widget.
///
/// A Live Activity rather than Now Playing on purpose. Claiming
/// MPNowPlayingInfoCenter would take the lock screen transport away from
/// Spotify — the app would be controlling a line while appearing to control
/// the music, and the music controls would stop working. A Live Activity sits
/// alongside whatever is playing and takes nothing from it.
struct LineActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Who is talking right now, if anybody.
        var speaker: String?
        var selfMuted: Bool
        var memberCount: Int
        var startedAt: Date
    }

    var squadName: String
    var code: String
}
