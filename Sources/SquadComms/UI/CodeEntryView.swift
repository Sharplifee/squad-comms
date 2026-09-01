import SwiftUI

/// Pick the squad code.
///
/// The code is not generated. It is whatever you and the people you train with
/// agree on — three digits is enough. A code you chose is one you can say out
/// loud across a gym floor and the other person can type without looking; a
/// random six-digit string has to be read off a screen every single time.
///
/// The code *is* the squad. Whoever opens it first creates it and everyone
/// after joins, so there is no host, no invite to accept, and no order anyone
/// has to do things in.
struct CodeEntryView: View {
    @EnvironmentObject private var session: SessionManager
    @State private var code = ""
    @State private var working = false
    @FocusState private var focused: Bool

    private let minimum = 3
    private let maximum = 8

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "number")
                .font(.system(size: 40))
                .foregroundStyle(Theme.accent)

            Text("Pick your squad code")
                .font(.title2.weight(.semibold))
                .padding(.top, 16)

            Text("Anything you'll remember. Everyone who types the same code lands on the same line.")
                .font(.subheadline)
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
                .padding(.top, 6)

            TextField("742", text: $code)
                .keyboardType(.numberPad)
                .font(.system(size: 52, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .kerning(6)
                .multilineTextAlignment(.center)
                .focused($focused)
                .padding(.vertical, 18)
                .padding(.top, 26)
                .onChange(of: code) { _, new in
                    code = String(new.filter(\.isNumber).prefix(maximum))
                }

            Text(hint)
                .font(.footnote)
                .foregroundStyle(code.count >= minimum ? Theme.textDim : Theme.textFaint)

            Spacer()

            Button {
                open()
            } label: {
                Group {
                    if working {
                        ProgressView().tint(.white)
                    } else {
                        Text("Open the line").font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .background(ready ? Theme.accent : Theme.surfaceAlt,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(ready ? .white : Theme.textFaint)
            .disabled(!ready || working)
            .padding(.horizontal, 24)
            .padding(.bottom, 34)
        }
        .background(Theme.background)
        .onAppear { focused = true }
    }

    private var ready: Bool { code.count >= minimum }

    private var hint: String {
        if code.isEmpty          { return "3 to 8 digits" }
        if code.count < minimum  { return "A bit longer — 3 digits minimum" }
        return "Share this with your squad"
    }

    private func open() {
        working = true
        Task {
            await session.joinOrCreate(code: code)
            working = false
        }
    }
}
