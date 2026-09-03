import SwiftUI

/// Design tokens.
///
/// Base is graphite rather than pure black — on OLED, true black makes every
/// card edge a hard seam and the whole interface reads as a set of floating
/// rectangles rather than one surface.
///
/// **One accent, and it means exactly one thing: live audio.** Mic hot,
/// somebody speaking, the transmit threshold. Nothing else may use it. That is
/// what makes a glance mid-set instant — if the yellow is showing, sound is
/// moving. Spending the accent on a chevron or a selected tab would destroy
/// the only signal in the app that has to be read without thinking.
enum Theme {

    // MARK: - Surfaces
    static let base       = Color(red: 0.078, green: 0.086, blue: 0.102)  // #14161A
    static let surface    = Color(red: 0.110, green: 0.122, blue: 0.145)  // #1C1F25
    static let raised     = Color(red: 0.137, green: 0.153, blue: 0.188)  // #232730
    static let line       = Color(red: 0.180, green: 0.200, blue: 0.239)  // #2E333D

    // MARK: - Text
    static let text       = Color(red: 0.949, green: 0.953, blue: 0.961)  // #F2F3F5
    static let muted      = Color(red: 0.541, green: 0.565, blue: 0.612)  // #8A909C
    static let dim        = Color(red: 0.353, green: 0.380, blue: 0.427)  // #5A616D

    // MARK: - Meaning
    /// LIVE AUDIO ONLY. See the note above before using this anywhere.
    static let signal     = Color(red: 0.922, green: 0.796, blue: 0.294)  // #EBCB4B
    static let danger     = Color(red: 0.898, green: 0.376, blue: 0.353)  // #E5605A

    // MARK: - Compatibility aliases
    // Older call sites still refer to these names. Mapped rather than
    // renamed everywhere at once, so the palette lands in one commit.
    static let background  = base
    static let surfaceAlt  = raised
    static let hairline    = line
    static let textDim     = muted
    static let textFaint   = dim
    static let accent      = text        // actions are white, not signal
    static let live        = signal
    static let warning     = signal

    static let corner: CGFloat = 18
    static let heroCorner: CGFloat = 22
    /// Rounded square, never a circle — a circle at this size reads as a chat
    /// avatar, and this is not a chat.
    static let avatarCorner: CGFloat = 13

    /// Distance bands fade rather than change hue. Colour-coding distance
    /// would need a second accent, and there is only one.
    static func color(for normalised: Double) -> Color {
        text.opacity(max(0.35, 1 - normalised * 0.55))
    }
}

extension View {
    func card() -> some View {
        self
            .padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }

    func stampLabel() -> some View {
        self.font(.footnote)
            .foregroundStyle(Theme.dim)
    }

    /// SF Rounded for the interface. Numbers and codes use tabular monospace
    /// so they do not shift width as they change.
    func interfaceFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> some View {
        self.font(.system(size: size, weight: weight, design: .rounded))
    }
}
