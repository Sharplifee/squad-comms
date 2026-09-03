import SwiftUI

/// The join screen is gone on purpose. squad comms opens straight into the
/// line. Bringing somebody in is an action you
/// take from inside the app (share the code, or enter theirs), not a wall you
/// stand behind before anything works.
struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.7 : 1),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundStyle(Theme.base)
    }
}
