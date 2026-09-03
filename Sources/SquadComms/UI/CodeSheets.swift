import SwiftUI

/// Entering a code is a deliberate choice from inside a working app, not the
/// price of admission.
struct SwitchSquadSheet: View {
    @EnvironmentObject private var session: SessionManager
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("742", text: $code)
                        .keyboardType(.numberPad)
                        .font(.title.monospaced())
                        .multilineTextAlignment(.center)
                        .focused($focused)
                        .onChange(of: code) { _, new in
                            code = String(new.filter(\.isNumber).prefix(8))
                        }
                        .submitLabel(.go)
                        .onSubmit {
                            guard code.count >= 3 else { return }
                            Task { await session.join(code: code); dismiss() }
                        }
                        .padding(.vertical, 8)
                } footer: {
                    Text("3 to 8 digits. You'll leave your current line. If nobody is on that code yet, you'll start it.")
                }
            }
            .navigationTitle("Switch code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
        .onAppear { focused = true }
    }
}

/// Starting a line. You choose the code here — it does not exist until now.
struct StartLineSheet: View {
    @EnvironmentObject private var session: SessionManager
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var working = false

    private let maximum = 8

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("Pick a code")
                    .font(.title2.weight(.semibold))
                    .padding(.top, 12)

                Text("3 to 8 digits. Anyone who types the same one lands with you.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textDim)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                    .padding(.top, 6)

                CodeBoxes(code: code, slots: max(3, min(code.count + 1, maximum)))
                    .padding(.vertical, 22)

                CodeKeypad(code: $code, maximum: maximum)
                    .padding(.horizontal, 40)

                Spacer(minLength: 12)

                Button {
                    working = true
                    Task {
                        await session.create(name: "\(PreferencesStore.shared.current.displayName)'s squad",
                                             code: code)
                        working = false
                        dismiss()
                    }
                } label: {
                    Group {
                        if working { ProgressView().tint(.white) }
                        else { Text("Open the line").font(.headline) }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                }
                .background(code.count >= 3 ? Theme.accent : Theme.surfaceAlt,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(code.count >= 3 ? Theme.base : Theme.dim)
                .disabled(code.count < 3 || working)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }
}
