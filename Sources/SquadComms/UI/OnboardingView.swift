import SwiftUI
import AVFoundation
import Speech
import CoreBluetooth

/// First run.
///
/// The app previously went straight to a live line having never asked anything,
/// which is why the squad was called "Me's squad" — Preferences.displayName
/// defaults to "Me" and nothing ever overwrote it. It also meant three system
/// permission prompts fired unexplained while the user was looking at a
/// spinner.
///
/// One screen, one button. Every permission is requested from that single tap,
/// in sequence, with the reason stated before it is asked for.
struct OnboardingView: View {
    @Binding var isComplete: Bool
    @State private var name = ""
    @State private var requesting = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Theme.accent)
                .padding(.bottom, 20)

            Text("Squadstream")
                .font(.largeTitle.bold())

            Text("An open line to the people you train with.\nYour music keeps playing and steps aside when someone talks.")
                .font(.subheadline)
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 8)

            Spacer()

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What should your squad call you?")
                        .font(.subheadline.weight(.medium))
                    TextField("Your name", text: $name)
                        .textContentType(.givenName)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .padding(12)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                }

                VStack(alignment: .leading, spacing: 12) {
                    permission("mic", "Microphone", "So your squad can hear you.")
                    permission("waveform", "Speech recognition", "For hands-free commands like \"mute\".")
                    permission("dot.radiowaves.left.and.right", "Bluetooth", "To see who's actually near you.")
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            Button {
                begin()
            } label: {
                if requesting {
                    ProgressView().tint(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                } else {
                    Text("Open the line")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
            .background(canContinue ? Theme.accent : Theme.surfaceAlt,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(canContinue ? .white : Theme.textFaint)
            .disabled(!canContinue || requesting)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .background(Theme.background)
        .onAppear { focused = true }
    }

    private var canContinue: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func permission(_ symbol: String, _ title: String, _ why: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.medium))
                Text(why).font(.caption).foregroundStyle(Theme.textDim)
            }
        }
    }

    /// Permissions are requested in sequence rather than all at once — iOS
    /// queues simultaneous prompts unpredictably and users dismiss the pile.
    private func begin() {
        requesting = true
        PreferencesStore.shared.update {
            $0.displayName = name.trimmingCharacters(in: .whitespaces)
        }

        AVAudioApplication.requestRecordPermission { _ in
            SFSpeechRecognizer.requestAuthorization { _ in
                DispatchQueue.main.async {
                    // Bluetooth has no request API — the prompt appears the
                    // first time a CBCentralManager is created, which happens
                    // when the line opens.
                    UserDefaults.standard.set(true, forKey: "squadcomms.onboarded")
                    requesting = false
                    isComplete = true
                }
            }
        }
    }
}
