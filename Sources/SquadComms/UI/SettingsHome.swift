import SwiftUI

/// Everything that isn't the line itself.
///
/// Absorbs the old Audio and Diagnostics tabs. Several controls that existed
/// two or three times over are now single: range lived in both the radar
/// header and the list header driving one value; intercom volume was settable
/// in the session screen and the Audio tab; sensitivity had a slider, a
/// draggable knob and a readout. Each is one control now, in one place.
struct SettingsHome: View {
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
            .scrollContentBackground(.hidden)
            .background(Theme.base)
            .navigationTitle("Settings")
            .tint(Theme.signal)
            .onChange(of: prefs) { old, new in
                PreferencesStore.shared.update { $0 = new }
                session.applyPreferences()
                if old.noiseSuppression != new.noiseSuppression { audio.audioSession.reapplyMode() }
                if old.selfMonitor != new.selfMonitor { audio.setSelfMonitorLevel(new.selfMonitor) }
                if old.visibility != new.visibility {
                    session.applyPresence()
                }
            }
        }
    }

    /// Six controls collapsed to one question with three answers.
    ///
    /// Duck amount, auto pause, pause after, auto rewind, rewind seconds and
    /// smart rewind were six ways to express a single preference about what
    /// should happen to your music, and every combination of them had to work.
    private var musicSection: some View {
        Section {
            ForEach(DuckBehavior.allCases) { behavior in
                Button {
                    prefs.duckBehavior = behavior
                    Haptics.selection()
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: prefs.duckBehavior == behavior
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(prefs.duckBehavior == behavior
                                             ? Theme.text : Theme.textFaint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(behavior.label)
                                .font(.system(size: 15, design: .rounded))
                                .foregroundStyle(Theme.text)
                            Text(behavior.detail)
                                .font(.system(size: 12.5, design: .rounded))
                                .foregroundStyle(Theme.textDim)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Your music while someone talks")
        } footer: {
            Text("Pause and rewind works with Apple Music, Podcasts and Voice Memos. Spotify and YouTube don't let any app move their playback, so there it just turns down.")
        }
    }

    /// One sensitivity handle, with the live number beside it.
    private var microphoneSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Sensitivity").font(.system(size: 15, design: .rounded))
                    Spacer()
                    Text("\(Int(prefs.vadOnsetDB)) dB · \(sensitivityWord)")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Theme.textDim)
                }
                Slider(value: Binding(
                    get: { Double(prefs.vadOnsetDB) },
                    set: { prefs.vadOnsetDB = Float($0) }
                ), in: -55 ... -12)
                .tint(Theme.signal)
                HStack {
                    Text("Whisper").font(.caption2).foregroundStyle(Theme.textFaint)
                    Spacer()
                    Text("Shout").font(.caption2).foregroundStyle(Theme.textFaint)
                }
            }
            .padding(.vertical, 2)

            slider("Hear yourself", value: $prefs.selfMonitor)
            slider("Squad volume", value: $prefs.intercomVolume)

            Picker("Clean up background noise", selection: $prefs.noiseSuppression) {
                ForEach(NoiseSuppression.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Microphone")
        }
    }

    /// Ghost mode and Private session were both "who can see me", so they are
    /// one control with three answers rather than two switches whose four
    /// combinations included two that made no sense.
    private var visibilitySection: some View {
        Section {
            Picker("Who can find you", selection: visibility) {
                Text("Visible nearby").tag(0)
                Text("Code only").tag(1)
                Text("Hidden").tag(2)
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("Who can find you")
        } footer: {
            Text(visibilityFooter)
        }
    }

    /// Reads and writes the SAME field SessionManager acts on.
    ///
    /// This previously wrote ghostMode and privateSession while the session
    /// read `visibility` — so the control moved, the footer changed, and
    /// nothing whatsoever happened. Exactly the class of bug that made the
    /// duck a no-op and the self-monitor silent.
    private var visibility: Binding<Int> {
        Binding(
            get: {
                switch prefs.visibility {
                case .visible:  return 0
                case .codeOnly: return 1
                case .hidden:   return 2
                }
            },
            set: { value in
                prefs.visibility = value == 2 ? .hidden : (value == 1 ? .codeOnly : .visible)
            }
        )
    }

    private var visibilityFooter: String {
        switch visibility.wrappedValue {
        case 2:  return "You won't appear on anyone's radar, and your stored location is deleted. People can still reach you with your code."
        case 1:  return "You won't be discovered nearby. Only someone with your code can join."
        default: return "People nearby with the app can see you on their radar."
        }
    }

    private var batterySection: some View {
        Section {
            Toggle("Low power mode", isOn: $prefs.lowPowerMode)
                .font(.system(size: 15, design: .rounded))
            Toggle("Sound cues", isOn: $prefs.soundCues)
                .font(.system(size: 15, design: .rounded))
        } header: {
            Text("Battery and feedback")
        } footer: {
            Text("Low power slows the radar once a line is open. Sound cues play a short tone when somebody joins or leaves, for when your phone's in a pocket.")
        }
    }

    private var safetySection: some View {
        // Two sections from one property needs a Group — without it the
        // opaque return type has nothing to infer from.
        Group {
            Section {
                NavigationLink { ContactsView(backend: session.backend) } label: {
                    Label("Find your contacts", systemImage: "person.crop.circle.badge.plus")
                }
            } header: {
                Text("Squad")
            } footer: {
                Text("See which of your contacts already have the app. Numbers are scrambled on your phone before anything is sent.")
            }

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
    }

    /// Diagnostics, demoted. It is where you look when something is wrong, not
    /// somewhere you navigate to on purpose.
    private var aboutSection: some View {
        Section {
            LabeledContent("Your name", value: prefs.displayName)
            LabeledContent("Output", value: audio.audioSession.routeName)
            LabeledContent("Version", value: version)
            NavigationLink { DiagnosticsView() } label: {
                Label("Connection details", systemImage: "waveform.path.ecg")
            }
        } header: {
            Text("About")
        }
    }

    // MARK: - Helpers

    private func slider(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: 15, design: .rounded))
                Spacer()
                Text("\(Int(value.wrappedValue * 100))%")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.textDim)
            }
            Slider(value: value, in: 0...1).tint(Theme.text)
        }
        .padding(.vertical, 2)
    }

    private var sensitivityWord: String {
        let words = ["Whisper", "Soft", "Low", "Medium", "Normal",
                     "Elevated", "Loud", "Very loud", "Shout"]
        let normalised = min(max(Double(prefs.vadOnsetDB + 55) / 43, 0), 1)
        return words[min(8, Int(normalised * 9))]
    }

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}
