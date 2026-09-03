import SwiftUI

/// Brief confirmations for things that leave no trace on screen.
///
/// Copying a code, muting everyone, switching route — the action happens
/// somewhere you cannot see, so without a word back you are left wondering
/// whether the tap registered. Deliberately short and deliberately above the
/// tab bar, where it cannot cover what you just pressed.
@MainActor
final class ToastCenter: ObservableObject {
    @Published private(set) var message: String?
    private var task: Task<Void, Never>?

    func show(_ text: String) {
        message = text
        Haptics.selection()
        task?.cancel()
        task = Task {
            try? await Task.sleep(nanoseconds: 1_700_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { message = nil }
        }
    }
}

struct ToastOverlay: ViewModifier {
    @ObservedObject var center: ToastCenter

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message = center.message {
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(.black.opacity(0.85), in: Capsule())
                    .padding(.bottom, 76)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.22), value: center.message)
    }
}

extension View {
    func toasts(_ center: ToastCenter) -> some View {
        modifier(ToastOverlay(center: center))
    }
}
