import SwiftUI

/// Colour comes from IWF competition plates, because a lifter already reads
/// those without thinking. Red is 25kg, blue 20kg, yellow 15kg, green 10kg.
/// Ground is the green-black of rubber gym flooring rather than pure black —
/// pure black on OLED makes every card edge a hard seam.
enum Theme {
    static let background = Color(red: 0.086, green: 0.098, blue: 0.090)   // #161917
    static let surface    = Color(red: 0.125, green: 0.141, blue: 0.122)   // #20241F
    static let surfaceAlt = Color(red: 0.149, green: 0.169, blue: 0.145)   // #262B25
    static let hairline   = Color(red: 0.173, green: 0.192, blue: 0.169)   // #2C312B

    static let plate25 = Color(red: 0.784, green: 0.204, blue: 0.180)      // #C8342E
    static let plate20 = Color(red: 0.180, green: 0.373, blue: 0.639)      // #2E5FA3
    static let plate15 = Color(red: 0.910, green: 0.725, blue: 0.231)      // #E8B93B
    static let plate10 = Color(red: 0.243, green: 0.561, blue: 0.322)      // #3E8F52

    /// Plates ordered as they load on a bar: heaviest closest to the collar.
    /// Band 0 is nearest to you, band 3 is furthest away.
    static let bands: [Color] = [plate25, plate20, plate15, plate10]
    static let bandWeights = [25, 20, 15, 10]

    static let accent   = plate20
    static let live     = plate10
    static let warning  = plate15
    static let muted    = plate25
    static let text     = Color(red: 0.929, green: 0.937, blue: 0.918)     // #EDEFEA
    static let textDim  = Color(red: 0.604, green: 0.643, blue: 0.588)     // #9AA396
    static let textFaint = Color(red: 0.431, green: 0.478, blue: 0.412)    // #6E7A69

    static let corner: CGFloat = 16

    /// Which plate band a normalised distance (0...1) falls into.
    static func band(for normalised: Double) -> Int {
        min(max(Int(normalised * 4), 0), 3)
    }
    static func color(for normalised: Double) -> Color {
        bands[band(for: normalised)]
    }
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

    /// Stamped-equipment label: condensed, wide-tracked, small.
    func stampLabel() -> some View {
        self.font(.system(size: 12, weight: .semibold))
            .tracking(1.1)
            .foregroundStyle(Theme.textDim)
    }
}
