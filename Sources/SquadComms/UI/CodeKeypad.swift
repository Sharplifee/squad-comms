import SwiftUI

/// Code entry with its own keypad.
///
/// The system number pad is a full-height keyboard for what is at most eight
/// digits, and it covers the boxes you are trying to fill. A purpose-built pad
/// keeps the code visible while you type it and puts the keys where a thumb
/// already is.
struct CodeKeypad: View {
    @Binding var code: String
    let maximum: Int

    private let rows = [["1","2","3"], ["4","5","6"], ["7","8","9"], ["", "0", "⌫"]]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(row, id: \.self) { key in
                        if key.isEmpty {
                            Color.clear.frame(maxWidth: .infinity, minHeight: 52)
                        } else {
                            Button {
                                press(key)
                            } label: {
                                Text(key)
                                    .font(.system(size: 24, weight: .regular, design: .rounded))
                                    .frame(maxWidth: .infinity, minHeight: 52)
                                    .background(Theme.surface,
                                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func press(_ key: String) {
        Haptics.selection()
        if key == "⌫" {
            if !code.isEmpty { code.removeLast() }
        } else if code.count < maximum {
            code.append(key)
        }
    }
}

/// The code as boxes, so its length is legible without counting characters.
struct CodeBoxes: View {
    let code: String
    let slots: Int

    var body: some View {
        HStack(spacing: 9) {
            ForEach(0..<slots, id: \.self) { index in
                let character = index < code.count
                    ? String(Array(code)[index]) : ""
                Text(character)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .frame(width: 46, height: 58)
                    .background(Theme.surface,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(index == code.count ? Theme.accent : .clear, lineWidth: 1.5)
                    )
            }
        }
        .animation(.snappy(duration: 0.15), value: code)
    }
}
