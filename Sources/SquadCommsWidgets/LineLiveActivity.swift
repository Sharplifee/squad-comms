import ActivityKit
import SwiftUI
import WidgetKit

/// The lock screen and Dynamic Island presentation of an open line.
///
/// Deliberately sparse. It is read at a glance, mid-set, upside down in a
/// pocket — so it carries one fact (who is talking, or that nobody is) and one
/// control (mute). Everything else is in the app.
struct LineLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LineActivityAttributes.self) { context in
            lockScreen(context)
                .activityBackgroundTint(Color(red: 0.078, green: 0.086, blue: 0.102))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.squadName, systemImage: "waveform")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.startedAt, style: .timer)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 54)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(headline(context.state))
                            .font(.headline)
                            .foregroundStyle(context.state.speaker != nil ? signal : .white)
                        Spacer()
                        muteButton(context.state.selfMuted)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.selfMuted ? "mic.slash.fill" : "waveform")
                    .foregroundStyle(context.state.speaker != nil ? signal : .white)
            } compactTrailing: {
                Text("\(context.state.memberCount)")
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: context.state.selfMuted ? "mic.slash.fill" : "waveform")
                    .foregroundStyle(context.state.speaker != nil ? signal : .white)
            }
        }
    }

    private var signal: Color { Color(red: 0.922, green: 0.796, blue: 0.294) }

    private func headline(_ state: LineActivityAttributes.ContentState) -> String {
        if let speaker = state.speaker { return "\(speaker) is talking" }
        if state.selfMuted { return "You're muted" }
        return "Line open"
    }

    private func lockScreen(_ context: ActivityViewContext<LineActivityAttributes>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: context.state.speaker != nil ? "waveform" : "dot.radiowaves.left.and.right")
                .font(.title3)
                .foregroundStyle(context.state.speaker != nil ? signal : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(headline(context.state))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("\(context.attributes.squadName) · \(context.state.memberCount) on")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()
            muteButton(context.state.selfMuted)
        }
        .padding(16)
    }

    /// An App Intent button, so muting never opens the app. Opening the app to
    /// mute is the thing this exists to avoid.
    private func muteButton(_ muted: Bool) -> some View {
        Button(intent: ToggleMuteIntent()) {
            Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
                .font(.system(size: 15))
                .frame(width: 44, height: 44)
                .background(muted ? Color.red.opacity(0.2) : Color.white.opacity(0.12), in: Circle())
                .foregroundStyle(muted ? .red : .white)
        }
        .buttonStyle(.plain)
    }
}

@main
struct SquadCommsWidgetBundle: WidgetBundle {
    var body: some Widget {
        LineLiveActivity()
    }
}
