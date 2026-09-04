import SwiftUI
import AVFoundation
import CoreBluetooth
import UIKit

/// What is actually happening underneath.
///
/// This app fails in ways that look identical from the outside — no audio
/// because Bluetooth routed to the speaker, because the mic permission was
/// denied, because LiveKit dropped, or because nobody is actually in the room.
/// One screen that names which, so a problem can be reported rather than
/// guessed at.
struct DiagnosticsView: View {
    @EnvironmentObject private var session: SessionManager
    @EnvironmentObject private var audio: AudioCoordinator
    @State private var copied = false
    @State private var selfTest: [AudioSelfTest.Check] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(selfTest) { check in
                        HStack(alignment: .top, spacing: 11) {
                            Image(systemName: check.passed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(check.passed ? Theme.signal : Theme.danger)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(check.name)
                                Text(check.detail)
                                    .font(.caption)
                                    .foregroundStyle(Theme.muted)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Audio check")
                } footer: {
                    // Reads the live session rather than the source, so it
                    // answers what is actually configured on this phone.
                    Text("Run this with music playing and somebody talking. It catches the configuration that made audio sound thin, which is the part that can be checked automatically — whether it sounds right is still your ear.")
                }

                Section("Connection") {
                    row("LiveKit", session.state == .connected ? "Connected" : "Not connected",
                        ok: session.state == .connected)
                    row("People in room", "\(session.members.count)",
                        ok: !session.members.isEmpty)
                    if let squad = session.squad {
                        row("Squad code", squad.joinCode, ok: true)
                    }
                    if let started = session.sessionStart {
                        row("Session length", elapsed(since: started), ok: true)
                    }
                }

                Section {
                    let probe = AudioProbe.read()
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: probe.healthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(probe.healthy ? Theme.signal : Theme.danger)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(probe.healthy ? "Audio path is correct" : "Audio path is wrong")
                                .font(.subheadline.weight(.semibold))
                            Text(probe.verdict)
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    row("Category", probe.category, ok: probe.category == "PlayAndRecord")
                    // .voiceChat on headphones is the exact v1 failure: it
                    // forces a telephony path and everything through it,
                    // music included, comes out thin.
                    row("Mode", probe.mode, ok: probe.mode != "VoiceChat")
                    row("Mixing", probe.options.contains("mixWithOthers") ? "Yes" : "NO",
                        ok: probe.options.contains("mixWithOthers"))
                    row("Ducking now", probe.ducking ? "Yes" : "No", ok: true)
                    row("Sample rate", "\(Int(probe.sampleRate)) Hz", ok: probe.sampleRate >= 44_100)
                    row("Buffer", String(format: "%.1f ms", probe.bufferMS), ok: probe.bufferMS <= 25)
                    row("Output", probe.route, ok: true)
                    row("Other audio", probe.otherAudioPlaying ? "Playing" : "None", ok: true)
                    row("Microphone", micPermission, ok: micGranted)
                    row("Input level", String(format: "%.0f dB", audio.inputLevelDB),
                        ok: audio.inputLevelDB > -55)
                } header: {
                    Text("Audio")
                } footer: {
                    Text("Play music, have somebody talk, and watch Ducking now. If Mode ever reads VoiceChat while you're on AirPods, that's the bug that made music sound thin.")
                }

                Section("Proximity") {
                    row("Bluetooth scanning", session.proximity.isScanning ? "On" : "Off",
                        ok: session.proximity.isScanning)
                    row("Devices seen", "\(session.proximity.contacts.count)",
                        ok: !session.proximity.contacts.isEmpty)
                    row("Range", ProximityEngine.rangeLabels[session.proximity.rangeIndex], ok: true)
                }

                Section("Device") {
                    row("Battery", batteryLabel, ok: UIDevice.current.batteryLevel > 0.2)
                    row("App version", version, ok: true)
                }

                Section {
                    Button {
                        Task { await session.reconnectIfNeeded() }
                        Haptics.impact(.medium)
                    } label: {
                        Label("Force reconnect", systemImage: "arrow.clockwise")
                    }
                    Button {
                        UIPasteboard.general.string = report
                        copied = true
                        Haptics.selection()
                    } label: {
                        Label(copied ? "Copied" : "Copy diagnostics",
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                } footer: {
                    Text("Copy this and send it if something isn't working — it says which layer failed.")
                }
            }
            .navigationTitle("Diagnostics")
            .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            selfTest = AudioSelfTest.run()
        }
        .refreshable { selfTest = AudioSelfTest.run() }
        }
    }

    private func row(_ label: String, _ value: String, ok: Bool) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(Theme.textDim)
            Circle()
                .fill(ok ? Theme.live : Theme.textFaint)
                .frame(width: 7, height: 7)
        }
    }

    private var audioRoute: String {
        AVAudioSession.sharedInstance().currentRoute.outputs.first?.portName ?? "Unknown"
    }
    private var micGranted: Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }
    private var micPermission: String {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return "Allowed"
        case .denied:  return "Denied"
        default:       return "Not asked"
        }
    }
    private var batteryLabel: String {
        let level = UIDevice.current.batteryLevel
        return level < 0 ? "Unknown" : "\(Int(level * 100))%"
    }
    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
    private func elapsed(since date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
    private var report: String {
        """
        Squadstream \(version)
        LiveKit: \(session.state == .connected ? "connected" : "not connected")
        Members: \(session.members.count)
        Output: \(audioRoute)
        Mic: \(micPermission)
        Input: \(String(format: "%.0f", audio.inputLevelDB)) dB
        Transmitting: \(audio.isTransmitting)
        BLE scanning: \(session.proximity.isScanning)
        Devices seen: \(session.proximity.contacts.count)
        Battery: \(batteryLabel)

        Audio check:
        \(selfTest.map { "  \($0.passed ? "ok" : "FAIL") \($0.name): \($0.detail)" }.joined(separator: "\n"))
        """
    }
}
