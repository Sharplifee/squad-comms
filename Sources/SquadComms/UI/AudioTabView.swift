import SwiftUI

/// Everything about what you hear and what they hear.
///
/// Split out of Settings because these are the controls you actually reach for
/// mid-session — how loud the squad is, how much your music drops, whether you
/// hear your own voice back. Burying them under a gear icon with your display
/// name and a permissions list made them feel like configuration rather than
/// the mixing desk they are.
struct AudioTabView: View {
    @EnvironmentObject private var session: SessionManager
    @EnvironmentObject private var audio: AudioCoordinator
    @State private var prefs = PreferencesStore.shared.current

    var body: some View {
        NavigationStack {
            List {
                Section {
                    slider("Squad volume", value: $prefs.intercomVolume,
                           symbol: "person.wave.2")
                } header: {
                    Text("How loud they are")
                } footer: {
                    Text("Applies to everyone at once. Individual people can still be turned up or down on the Squad tab.")
                }

                Section {
                    slider("Hear yourself", value: $prefs.selfMonitor,
                           symbol: "ear")
                } footer: {
                    Text("A little of your own voice back through the headphones so you don't shout. Around 20% is natural.")
                }

                Section {
                    ForEach(DuckBehavior.allCases) { behavior in
                        Button {
                            prefs.duckBehavior = behavior
                            Haptics.selection()
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: prefs.duckBehavior == behavior
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(prefs.duckBehavior == behavior ? Theme.accent : Theme.textFaint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(behavior.label).foregroundStyle(Theme.text)
                                    Text(behavior.detail)
                                        .font(.footnote)
                                        .foregroundStyle(Theme.textDim)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    if prefs.duckBehavior == .duck {
                        HStack {
                            Text("Drop to")
                            Spacer()
                            Text("\(Int(prefs.duckLevel * 100))%")
                                .foregroundStyle(Theme.textDim)
                                .monospacedDigit()
                        }
                        Slider(value: $prefs.duckLevel, in: 0...0.6, step: 0.05)
                    }
                } header: {
                    Text("When someone talks")
                } footer: {
                    Text("Only changes what you hear. It doesn't affect anyone else.")
                }

                Section {
                    Toggle("Pause if they keep talking", isOn: $prefs.autoPause)
                    if prefs.autoPause {
                        Stepper("After \(Int(prefs.autoPauseSeconds)) seconds",
                                value: $prefs.autoPauseSeconds, in: 3...30, step: 1)
                    }
                    Toggle("Rewind when they finish", isOn: $prefs.autoRewind)
                    if prefs.autoRewind {
                        Stepper("Back \(Int(prefs.rewindSeconds)) seconds",
                                value: $prefs.rewindSeconds, in: 3...30, step: 1)
                    }
                } header: {
                    Text("Long interruptions")
                } footer: {
                    // Stated plainly because it is the single most common
                    // support question and there is no way to fix it: no app
                    // can seek another app's playback.
                    Text("Rewind works with Apple Music, Podcasts and Voice Memos. Spotify and YouTube don't let any app move their playback, so it's skipped there.")
                }

                Section {
                    Picker("Noise suppression", selection: $prefs.noiseSuppression) {
                        ForEach(NoiseSuppression.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(prefs.noiseSuppression.detail)
                        .font(.footnote)
                        .foregroundStyle(Theme.textDim)
                } header: {
                    Text("Your microphone")
                }

                Section {
                    LabeledContent("Input level",
                                   value: String(format: "%.0f dB", audio.inputLevelDB))
                    LabeledContent("Sample rate", value: "48 kHz")
                    LabeledContent("Buffer", value: "5 ms")
                } header: {
                    Text("Advanced")
                }
            }
            .navigationTitle("Audio")
            .onChange(of: prefs) { old, new in
                PreferencesStore.shared.update { $0 = new }
                session.applyPreferences()
                if old.noiseSuppression != new.noiseSuppression {
                    audio.audioSession.reapplyMode()
                }
                if old.selfMonitor != new.selfMonitor {
                    audio.setSelfMonitorLevel(new.selfMonitor)
                }
            }
        }
    }

    private func slider(_ title: String, value: Binding<Double>, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                Text("\(Int(value.wrappedValue * 100))%")
                    .foregroundStyle(Theme.textDim)
                    .monospacedDigit()
            }
            Slider(value: value, in: 0...1)
        }
        .padding(.vertical, 2)
    }
}
