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

    var body: some View {
        NavigationStack {
            List {
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

                Section("Audio") {
                    row("Output", audioRoute, ok: true)
                    row("Microphone", micPermission, ok: micGranted)
                    row("Input level", String(format: "%.0f dB", audio.inputLevelDB),
                        ok: audio.inputLevelDB > -55)
                    row("Transmitting", audio.isTransmitting ? "Yes" : "No",
                        ok: audio.isTransmitting)
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
            .onAppear { UIDevice.current.isBatteryMonitoringEnabled = true }
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
        """
    }
}
