import UIKit

/// Physical confirmation for actions taken without looking at the screen.
///
/// The whole point of this app is that your phone stays in your pocket, so a
/// private line opening or closing needs a signal you can feel. Generators are
/// prepared before use — an unprepared generator has a noticeable lag on the
/// first fire, which defeats the purpose.
enum Haptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }
}
