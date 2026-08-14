import SwiftUI

struct JoinView: View {
    @EnvironmentObject private var session: SessionManager
    @State private var code = ""
    @State private var squadName = ""
    @State private var creating = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 10) {
                Text("squad comms")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                Text("Your headphones, but your people can get through.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if creating {
                VStack(spacing: 14) {
                    TextField("Name your squad", text: $squadName)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 14)
                        .background(Theme.surfaceAlt, in: RoundedRectangle(cornerRadius: 12))
                        .focused($focused)

                    Button("Open the line") {
                        Task { await session.create(name: squadName.isEmpty ? "My squad" : squadName) }
                    }
                    .buttonStyle(PrimaryButton())

                    Button("I have a code") { creating = false }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .card()
            } else {
                VStack(spacing: 14) {
                    Text("Enter your squad's 6-digit code")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    TextField("000000", text: $code)
                        .textFieldStyle(.plain)
                        .keyboardType(.numberPad)
                        .font(.system(size: 40, weight: .semibold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .focused($focused)
                        .onChange(of: code) { _, new in
                            code = String(new.filter(\.isNumber).prefix(6))
                            if code.count == 6 { Task { await session.join(code: code) } }
                        }

                    Button("Start a new squad") { creating = true }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .card()
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .onAppear { focused = true }
    }
}

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.7 : 1),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundStyle(.white)
    }
}
