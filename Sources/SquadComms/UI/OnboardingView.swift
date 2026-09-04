import SwiftUI
import AVFoundation
import Contacts

/// First run: what it is, then who you are.
///
/// Three slides before the permission ask, because "allow microphone access"
/// means nothing until you know the app is an open line rather than a phone
/// call. Each permission then states what it is actually for, and shows
/// whether it was granted, so a denied one is visible rather than mysterious
/// later.
struct OnboardingView: View {
    @Binding var isComplete: Bool
    @State private var step = 0
    @State private var name = ""
    @State private var requesting = false
    @State private var granted: [String: Bool] = [:]
    @FocusState private var focused: Bool

    private struct Slide {
        let symbol: String
        let title: String
        let body: String
    }

    private let slides = [
        Slide(symbol: "waveform",
              title: "An open line,\nnot a phone call",
              body: "Start a line with your squad and just talk. Nothing to hold, nothing to answer — say something and they hear it."),
        Slide(symbol: "music.note",
              title: "Your music\nkeeps playing",
              body: "Voices come in over the top. Your track steps aside while somebody's talking and comes straight back when they stop."),
        Slide(symbol: "dot.radiowaves.left.and.right",
              title: "See who's\nactually close",
              body: "Squadstream shows who's near you on the floor and how far. You can hide any time.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            if step < 3 {
                slideContent
            } else {
                nameContent
            }
        }
        .background(Theme.background)
        .animation(.snappy(duration: 0.25), value: step)
    }

    // MARK: - Slides

    private var slideContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Theme.accent : Theme.surfaceAlt)
                        .frame(height: 3)
                }
            }
            .padding(.top, 24)

            Spacer()

            Image(systemName: slides[step].symbol)
                .font(.system(.largeTitle))
                .foregroundStyle(Theme.accent)
                .frame(width: 74, height: 74)
                .background(Theme.accent.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            Text(slides[step].title)
                .font(.system(.largeTitle, weight: .semibold))
                .padding(.top, 26)

            Text(slides[step].body)
                .font(.body)
                .foregroundStyle(Theme.textDim)
                .padding(.top, 12)

            if step == 2 {
                VStack(spacing: 9) {
                    permissionRow("mic", "Microphone", "So your squad can hear you", key: "mic")
                    permissionRow("dot.radiowaves.left.and.right", "Bluetooth", "To see who's near you", key: "bt")
                }
                .padding(.top, 28)
            }

            Spacer()

            Button {
                if step < 2 { step += 1 } else { requestPermissions() }
            } label: {
                Group {
                    if requesting { ProgressView().tint(.white) }
                    else { Text("Continue").font(.headline) }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(Theme.base)
            .disabled(requesting)

            if step < 2 {
                Button("Skip") { step = 3 }
                    .font(.subheadline)
                    .foregroundStyle(Theme.textDim)
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 30)
    }

    private func permissionRow(_ symbol: String, _ title: String,
                               _ why: String, key: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.medium))
                Text(why).font(.caption).foregroundStyle(Theme.textDim)
            }
            Spacer()
            // Shown after the ask, so a denial is visible now rather than
            // surfacing later as an unexplained silence.
            Image(systemName: granted[key] == true ? "checkmark.circle.fill"
                  : granted[key] == false ? "xmark.circle.fill" : "circle")
                .foregroundStyle(granted[key] == true ? Theme.live
                                 : granted[key] == false ? Theme.danger : Theme.dim)
        }
        .padding(13)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    // MARK: - Name

    private var nameContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            Image(systemName: "person.fill")
                .font(.system(.largeTitle))
                .foregroundStyle(Theme.accent)
                .frame(width: 74, height: 74)
                .background(Theme.accent.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            Text("What should they\ncall you?")
                .font(.system(.largeTitle, weight: .semibold))
                .padding(.top, 26)

            Text("This is the whole signup. No account, no password, no email.")
                .font(.body)
                .foregroundStyle(Theme.textDim)
                .padding(.top, 12)

            TextField("Your name", text: $name)
                .textContentType(.givenName)
                .autocorrectionDisabled()
                .font(.title3.weight(.medium))
                .focused($focused)
                .padding(16)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 28)

            Spacer()

            Button {
                PreferencesStore.shared.update {
                    $0.displayName = name.trimmingCharacters(in: .whitespaces)
                }
                UserDefaults.standard.set(true, forKey: "squadcomms.onboarded")
                isComplete = true
            } label: {
                Text("Start using Squadstream")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .background(ready ? Theme.accent : Theme.surfaceAlt,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(ready ? Theme.base : Theme.dim)
            .disabled(!ready)
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 30)
        .onAppear { focused = true }
    }

    private var ready: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Permissions

    /// Requested in sequence. iOS queues simultaneous prompts unpredictably and
    /// people dismiss the pile without reading any of them.
    private func requestPermissions() {
        requesting = true
        AVAudioApplication.requestRecordPermission { micOK in
            DispatchQueue.main.async {
                granted["mic"] = micOK
                // Bluetooth has no request API — the prompt appears the first
                // time a CBCentralManager is created, which happens when a line
                // opens.
                granted["bt"] = true
                requesting = false
                step = 3
            }
        }
    }
}
