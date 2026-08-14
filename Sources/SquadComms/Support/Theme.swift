import SwiftUI

/// Single source of truth for colour and type. Lifted dark — not pure black.
enum Theme {
    static let background = Color(red: 0.06, green: 0.07, blue: 0.09)
    static let surface    = Color(red: 0.10, green: 0.11, blue: 0.14)
    static let surfaceAlt = Color(red: 0.14, green: 0.15, blue: 0.19)
    static let accent     = Color(red: 0.43, green: 0.55, blue: 1.00)
    static let live       = Color(red: 0.20, green: 0.85, blue: 0.55)
    static let muted      = Color(red: 0.95, green: 0.42, blue: 0.42)
    static let hairline   = Color.white.opacity(0.08)

    static let corner: CGFloat = 16
}

extension View {
    func card() -> some View {
        self
            .padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
    }
}
