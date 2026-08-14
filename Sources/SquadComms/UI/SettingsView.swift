import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var prefs = PreferencesStore.shared.current

    var body: some View {
        NavigationStack {
            Form {
                Section("Your name") {
                    TextField("What your squad sees", text: $prefs.displayName)
                }

                Section {
                    ForEach(DuckBehavior.allCases) { behavior in
                        Button {
                            prefs.duckBehavior = behavior
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: prefs.duckBehavior == behavior
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(prefs.duckBehavior == behavior ? Theme.accent : .secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(behavior.label).foregroundStyle(.primary)
                                    Text(behavior.detail)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    if prefs.duckBehavior == .rewind {
                        Stepper("Rewind \(Int(prefs.rewindSeconds)) seconds",
                                value: $prefs.rewindSeconds, in: 3...30, step: 1)
                    }
                } header: {
                    Text("When someone talks")
                } footer: {
                    Text("This only changes what you hear. It doesn't affect anyone else in the squad.")
                }

                Section {
                    Toggle("Open mic", isOn: $prefs.openMic)
                    Text(prefs.openMic
                         ? "Just talk. Your voice goes through on its own."
                         : "Hold the button on the main screen to talk.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("How you talk")
                }

                Section {
                    Toggle("Voice commands", isOn: $prefs.voiceCommandsEnabled)
                    if prefs.voiceCommandsEnabled {
                        ForEach(CommandEngine.Command.allCases, id: \.rawValue) { command in
                            Text("\"\(command.rawValue)\"")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Hands-free")
                } footer: {
                    Text("Say any of these out loud and it happens without touching your phone.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        PreferencesStore.shared.update { $0 = prefs }
                        dismiss()
                    }
                }
            }
        }
    }
}
