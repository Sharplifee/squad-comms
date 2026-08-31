import SwiftUI
import Combine

/// Silence the squad for a fixed stretch.
///
/// Muting everyone works but you have to remember to undo it, and the moment
/// you need it most — a heavy set — is exactly when you will forget. Focus is
/// muting with an expiry, so the line always comes back on its own.
@MainActor
final class FocusModeController: ObservableObject {
    @Published private(set) var remaining: Int = 0
    var isActive: Bool { remaining > 0 }

    private var timer: AnyCancellable?
    private weak var session: SessionManager?

    func attach(_ session: SessionManager) { self.session = session }

    static let durations = [30, 60, 90, 120]

    func begin(seconds: Int) {
        session?.muteAll(true)
        remaining = seconds
        Haptics.impact(.medium)

        timer?.cancel()
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                remaining -= 1
                if remaining <= 0 { self.end() }
            }
    }

    func end() {
        timer?.cancel(); timer = nil
        remaining = 0
        session?.muteAll(false)
        Haptics.impact(.rigid)
    }
}

/// Full-screen countdown. Deliberately large and unmissable — if focus is on,
/// you are not hearing your squad, and that has to be obvious from a glance
/// across a gym floor.
struct FocusOverlay: View {
    @ObservedObject var focus: FocusModeController

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "moon.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent)

            Text("\(focus.remaining)")
                .font(.system(size: 88, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy, value: focus.remaining)

            Text("Squad muted")
                .font(.headline)
            Text("The line comes back on its own.")
                .font(.subheadline)
                .foregroundStyle(Theme.textDim)

            Button("End now") { focus.end() }
                .buttonStyle(.bordered)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .transition(.opacity)
    }
}

/// The trigger, as a menu so a duration is one tap rather than a sheet.
struct FocusButton: View {
    @ObservedObject var focus: FocusModeController

    var body: some View {
        Menu {
            ForEach(FocusModeController.durations, id: \.self) { seconds in
                Button("\(seconds) seconds") { focus.begin(seconds: seconds) }
            }
        } label: {
            Label("Focus", systemImage: "moon")
        }
    }
}
