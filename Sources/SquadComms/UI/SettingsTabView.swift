import SwiftUI

/// Everything that isn't the line or the people on it.
///
/// Absorbs the old Audio, Diagnostics and Contacts tabs. Diagnostics is
/// something you open when something is wrong, not a destination worth a fifth
/// of the tab bar.
///
/// The redundancies the brief called out are resolved here rather than
/// preserved: music handling was six separate controls answering one question,
/// visibility was two toggles that were really one three-way choice, and
/// sensitivity was settable three different ways.
struct SettingsTabView: View {
    @EnvironmentObject private var session: SessionManager
    @EnvironmentObject private var audio: AudioCoordinator
    @State private var prefs = PreferencesStore.shared.current

    var body: some View {
        NavigationStack {
            List {
                musicSection
                microphoneSection
                visibilitySection
                batterySection
                safetySection
                aboutSection
            }
            .navigationTitle("Settings")
            .onChange(of: prefs) { old, new in
                PreferencesStore.shared.update { $0 = new }
                session.applyPreferences()
                if old.noiseSuppression != new.noiseSuppression { audio.audioSession.reapplyMode() }
                if old.selfMonitor != new.selfMonitor { audio.setSelfMonitorLevel(new.selfMonitor) }
                if old.visibility != new.visibility { session.applyPresence() }
            }
        }
    }

    /// One question, three answers. It was six controls — duck amount, auto
    /// pause, pause after, auto rewind, rewind seconds, smart rewind — for a
    /// decision nobody makes more than once.
    private var musicSection: some View {
        Section {
            ForEach(MusicBehaviour.allCases) { option in
                Button {
                    prefs.musicBehaviour = option
                    Haptics.selection()
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: prefs.musicBehaviour == option
                              ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(prefs.musicBehaviour == option ? Theme.text : Theme.dim)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.title).foregroundStyle(Theme.text)
                            Text(option.detail)
                                .font(.footnote)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Your music while someone talks")
        } footer: {
            Text("Rewind works with Apple Music, Podcasts and Voice Memos. Spotify and YouTube don't let any app move their playback, so it's skipped there.")
        }
    }

    private var microphoneSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("You trigger at")
                    Spacer()
                    Text("\(Int(prefs.vadOnsetDB)) dB · \(sensitivityWord)")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                }
                // One handle. It used to be settable from a pill, a draggable
                // knob and an advanced readout, all driving the same number.
                Slider(value: Binding(get: { Double(prefs.vadOnsetDB) },
                                      set: { prefs.vadOnsetDB = Float($0) }),
                       in: -55 ... -12)
                    .tint(Theme.signal)
                HStack {
                    Text("Whisper").font(.caption2).foregroundStyle(Theme.dim)
                    Spacer()
                    Text("Shout").font(.caption2).foregroundStyle(Theme.dim)
                }
            }
            .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Hear yourself")
                    Spacer()
                    Text("\(Int(prefs.selfMonitor * 100))%")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                }
                Slider(value: $prefs.selfMonitor, in: 0...0.45).tint(Theme.text)
            }
            .padding(.vertical, 2)

            Picker("Clean up background noise", selection: $prefs.noiseSuppression) {
                ForEach(NoiseSuppression.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Microphone")
        } footer: {
            Text(prefs.noiseSuppression.detail)
        }
    }

    /// Ghost mode and private session were both "who can see me", so they are
    /// one control with three answers rather than two toggles with an
    /// ambiguous combined state.
    private var visibilitySection: some View {
        Section {
            Picker("Who can find you", selection: $prefs.visibility) {
                ForEach(Visibility.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("Who can find you")
        } footer: {
            Text(prefs.visibility.detail)
        }
    }

    private var batterySection: some View {
        Section {
            Toggle("Low power mode", isOn: $prefs.lowPowerMode)
            Toggle("Sound cues", isOn: $prefs.soundCues)
        } header: {
            Text("Battery and feedback")
        } footer: {
            Text("Low power slows the radar once a line is open. Sound cues play a short tone when someone joins or leaves, for when your phone is in a pocket.")
        }
    }

    private var safetySection: some View {
        Section {
            NavigationLink { BlockedListView() } label: {
                Label("Blocked", systemImage: "hand.raised")
            }
            NavigationLink { DeleteDataView() } label: {
                Label("Your data", systemImage: "trash")
            }
        } header: {
            Text("Safety and privacy")
        }
    }

    /// Diagnostics, demoted from a tab to a row. You open this when something
    /// is wrong, which is rare, and it should not cost a fifth of the tab bar.
    private var aboutSection: some View {
        Section {
            TextField("Your name", text: $prefs.displayName)
            NavigationLink { DiagnosticsView() } label: {
                Label("Connection", systemImage: "waveform.path.ecg")
            }
            LabeledContent("Version", value: version)
        } header: {
            Text("About")
        }
    }

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    private var sensitivityWord: String {
        let words = ["Whisper", "Soft", "Low", "Medium", "Normal",
                     "Elevated", "Loud", "Very loud", "Shout"]
        let t = min(max(Double(prefs.vadOnsetDB + 55) / 43, 0), 1)
        return words[min(8, Int(t * 9))]
    }
}
