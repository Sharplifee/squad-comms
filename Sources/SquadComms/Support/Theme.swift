import SwiftUI

/// Design tokens.
///
/// Base is graphite rather than pure black: on OLED, true black makes every
/// card edge a hard seam, and this app is mostly cards.
///
/// **One accent, reserved exclusively for live audio.** Signal yellow means
/// exactly one thing — the mic is hot, somebody is speaking, or that is the
/// threshold where your voice starts going out. Nothing else may use it, which
/// is what lets a glance mid-set read instantly instead of being decoded.
/// Every other affordance is greyscale, and destructive is the only other
/// coloured exception.
enum Theme {

    // MARK: - Surfaces
    static let base    = Color(red: 0.078, green: 0.086, blue: 0.102)  // #14161A
    static let surface = Color(red: 0.110, green: 0.122, blue: 0.145)  // #1C1F25
    static let raised  = Color(red: 0.137, green: 0.153, blue: 0.188)  // #232730
    static let line    = Color(red: 0.180, green: 0.200, blue: 0.239)  // #2E333D

    // Names the rest of the app already uses, kept pointing at the new values
    // so this is a re-skin rather than a rename sweep.
    static let background = base
    static let surfaceAlt = raised
    static let hairline   = line

    // MARK: - Text
    static let text     = Color(red: 0.949, green: 0.953, blue: 0.961)  // #F2F3F5
    static let textDim  = Color(red: 0.541, green: 0.565, blue: 0.612)  // #8A909C
    static let textFaint = Color(red: 0.353, green: 0.380, blue: 0.427) // #5A616D

    // MARK: - Meaning
    /// LIVE AUDIO ONLY. Mic hot, someone speaking, threshold marker.
    static let signal = Color(red: 0.922, green: 0.796, blue: 0.294)    // #EBCB4B
    static let danger = Color(red: 0.898, green: 0.376, blue: 0.353)    // #E5605A

    // Legacy aliases. accent is deliberately NOT signal — signal is spoken
    // for, so ordinary interactive things use plain text weight instead of a
    // second colour competing with it.
    static let accent  = text
    static let live    = signal
    static let warning = signal
    static let muted   = danger

    /// Aliases used by screens written against the v2 token names.
    static let dim          = textFaint
    static let avatarCorner: CGFloat = 13

    static let corner: CGFloat = 18

    // MARK: - Radar bands
    static let bands: [Color] = [signal, signal, signal, signal]
    static let bandWeights    = [1, 2, 3, 4]
    static func bandOpacity(_ index: Int) -> Double { [0.55, 0.38, 0.24, 0.14][min(index, 3)] }

    static func band(for normalised: Double) -> Int { min(max(Int(normalised * 4), 0), 3) }
    static func color(for normalised: Double) -> Color {
        text.opacity(1 - normalised * 0.45)
    }
}

extension View {
    func card() -> some View {
        self
            .padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    func stampLabel() -> some View {
        self.font(.footnote).foregroundStyle(Theme.textFaint)
    }

    /// SF Rounded for the interface. Numbers and codes use monospace instead,
    /// so a code never reflows as its digits change.
    func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> some View {
        self.font(.system(size: size, weight: weight, design: .rounded))
    }
}
