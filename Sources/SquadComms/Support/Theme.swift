import SwiftUI

/// Design tokens.
///
/// Everything here resolves to a system semantic colour rather than a fixed
/// hex value, so the app inherits Apple's light and dark palettes, contrast
/// settings and future OS changes for free. A hand-picked dark palette looks
/// deliberate in a screenshot and wrong on a real device the moment someone
/// turns on Increase Contrast or uses the app outdoors in daylight.
///
/// One accent colour, used only for things that are live or actionable.
/// Everything else is greyscale, which is what makes the accent mean anything.
enum Theme {

    // MARK: - Surfaces
    static let background  = Color(.systemGroupedBackground)
    static let surface     = Color(.secondarySystemGroupedBackground)
    static let surfaceAlt  = Color(.tertiarySystemGroupedBackground)
    static let hairline    = Color(.separator)

    // MARK: - Text
    static let text        = Color.primary
    static let textDim     = Color.secondary
    static let textFaint   = Color(.tertiaryLabel)

    // MARK: - Meaning
    /// Actionable and live. Kept to the system tint so the app matches every
    /// other app on the device.
    static let accent      = Color.accentColor
    /// Someone is transmitting.
    static let live        = Color.green
    /// A direct line — the one state that must never be mistaken for the group.
    static let warning     = Color.orange
    /// Muted or destructive.
    static let muted       = Color.red

    // MARK: - Radar range bands
    /// Distance bands fade with distance rather than changing hue. Colour-coding
    /// rings by hue implies categories that do not exist — there is only near
    /// and far, and opacity says that without inventing meaning.
    static let bands: [Color]  = [accent, accent, accent, accent]
    static let bandWeights     = [1, 2, 3, 4]
    static func bandOpacity(_ index: Int) -> Double { [0.55, 0.38, 0.24, 0.14][min(index, 3)] }

    static let corner: CGFloat = 12

    static func band(for normalised: Double) -> Int {
        min(max(Int(normalised * 4), 0), 3)
    }
    static func color(for normalised: Double) -> Color {
        accent.opacity(bandOpacity(band(for: normalised)) + 0.35)
    }
}

extension View {
    /// A grouped-list style container. Matches the inset cards the system uses
    /// in Settings, Health and Fitness, including the corner radius.
    func card() -> some View {
        self
            .padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }

    /// Section headers use the system's own uppercase footnote treatment rather
    /// than letter-spaced stencil type — the same as every Settings screen.
    func stampLabel() -> some View {
        self.font(.footnote)
            .foregroundStyle(Theme.textDim)
    }
}
