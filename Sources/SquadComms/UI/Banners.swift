import SwiftUI
import AVFoundation
import CoreBluetooth

/// Conditions that stop the app working, stated where you are already looking.
///
/// These matter more here than in most apps because the failure mode is
/// silence — a denied microphone or a dropped network produces no error, just
/// a line where nobody ever says anything. Without a banner the app looks like
/// it is working and your squad looks like they are ignoring you.
struct ConditionBanners: View {
    @EnvironmentObject private var session: SessionManager
    @EnvironmentObject private var audio: AudioCoordinator
    @ObservedObject private var conditions = AppConditions.shared

    var body: some View {
        VStack(spacing: 9) {
            if !conditions.online {
                banner(symbol: "wifi.slash",
                       title: "No connection",
                       detail: "You can't open or join a line until you're back online. Everything you've set is saved.",
                       tint: Theme.danger)
            }

            if conditions.micDenied {
                banner(symbol: "mic.slash.fill",
                       title: "Microphone is off",
                       detail: "Nobody can hear you. Squad comms needs the mic to work at all.",
                       tint: Theme.danger,
                       action: ("Open Settings", openSettings))
            }

            if conditions.bluetoothDenied {
                banner(symbol: "dot.radiowaves.left.and.right",
                       title: "Bluetooth is off",
                       detail: "The radar can't see anyone nearby. Talking still works.",
                       tint: Theme.signal,
                       action: ("Open Settings", openSettings))
            }

            // Something you just tried did not work. Dismissible, inline, and
            // it never stops you doing anything else.
            if let notice = session.notice {
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(.subheadline))
                        .foregroundStyle(Theme.signal)
                    Text(notice)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button {
                        session.notice = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(.caption2, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .padding(14)
                .background(Theme.signal.opacity(0.11),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.signal.opacity(0.3), lineWidth: 1))
            }

            if session.endedByHost {
                banner(symbol: "phone.down.fill",
                       title: "The line was closed",
                       detail: "Whoever started it ended the session for everyone.",
                       tint: Theme.signal)
            }
        }
    }

    private func banner(symbol: String, title: String, detail: String,
                        tint: Color, action: (String, () -> Void)? = nil) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbol)
                .font(.system(.subheadline))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                Text(detail)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let action {
                    Button(action.0, action: action.1)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(tint.opacity(0.3), lineWidth: 1))
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

/// Watches the conditions that silently break the app.
///
/// Permissions are re-checked whenever the app returns to the foreground,
/// because they can be revoked in Settings while it is running — which
/// produces a session that looks connected and transmits nothing.
@MainActor
final class AppConditions: ObservableObject {
    static let shared = AppConditions()

    @Published private(set) var online = true
    @Published private(set) var micDenied = false
    @Published private(set) var bluetoothDenied = false

    private var timer: Timer?

    private init() { refresh() }

    func refresh() {
        online = NetworkReachability.isOnline
        micDenied = AVAudioApplication.shared.recordPermission == .denied
        let bt = CBCentralManager.authorization
        bluetoothDenied = (bt == .denied || bt == .restricted)
    }

    /// Poll while in the foreground. Reachability has no cheap synchronous
    /// change notification worth wiring for this, and once every few seconds
    /// is plenty for a banner.
    func startWatching() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stopWatching() {
        timer?.invalidate(); timer = nil
    }
}
