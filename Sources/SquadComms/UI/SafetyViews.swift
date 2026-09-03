import SwiftUI

/// Reporting somebody on a live audio channel.
///
/// Apple requires this for user-generated content, but the reason it has to be
/// good rather than merely present is that the person using it is having a bad
/// experience right now, in their ear, and the flow should take seconds.
struct ReportSheet: View {
    let member: Member
    @EnvironmentObject private var session: SessionManager
    @Environment(\.dismiss) private var dismiss
    @State private var reason = "abusive_audio"
    @State private var detail = ""
    @State private var sending = false

    private let reasons: [(String, String)] = [
        ("abusive_audio",   "Abusive or threatening"),
        ("harassment",      "Harassment"),
        ("sexual_content",  "Sexual content"),
        ("impersonation",   "Pretending to be someone else"),
        ("spam",            "Spam"),
        ("other",           "Something else")
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(reasons, id: \.0) { value, label in
                        Button {
                            reason = value
                            Haptics.selection()
                        } label: {
                            HStack {
                                Text(label).foregroundStyle(Theme.text)
                                Spacer()
                                if reason == value {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                }
                            }
                        }
                    }
                } header: {
                    Text("What happened?")
                }

                Section {
                    TextField("Anything else we should know", text: $detail, axis: .vertical)
                        .lineLimit(3...6)
                } footer: {
                    Text("Reporting also blocks \(member.displayName). They won't be able to reach you again, on this line or any other.")
                }

                Section {
                    Button(role: .destructive) {
                        send()
                    } label: {
                        HStack {
                            Spacer()
                            if sending { ProgressView() } else { Text("Report and block") }
                            Spacer()
                        }
                    }
                    .disabled(sending)
                }
            }
            .navigationTitle("Report \(member.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }

    private func send() {
        sending = true
        Task {
            await session.report(member: member, reason: reason,
                                 detail: detail.isEmpty ? nil : detail)
            sending = false
            dismiss()
        }
    }
}

/// Everyone you've blocked, and the way back.
struct BlockedListView: View {
    @EnvironmentObject private var session: SessionManager
    @State private var blocked: [Backend.BlockedRow] = []
    @State private var loading = true

    var body: some View {
        List {
            if loading {
                HStack(spacing: 10) { ProgressView(); Text("Loading").foregroundStyle(Theme.textDim) }
            } else if blocked.isEmpty {
                ContentUnavailableView("Nobody blocked", systemImage: "hand.raised",
                                       description: Text("People you block won't be able to reach you on any line."))
            } else {
                ForEach(blocked) { row in
                    HStack {
                        Text(row.displayName)
                        Spacer()
                        Button("Unblock") {
                            Task {
                                await session.unblock(deviceID: row.deviceID)
                                await load()
                            }
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
        .navigationTitle("Blocked")
        .task { await load() }
    }

    private func load() async {
        blocked = await session.blockedList()
        loading = false
    }
}

/// Erasing everything the server holds about this device.
///
/// There is no account to delete, which is exactly why this has to be explicit
/// — otherwise there is no visible way to leave.
struct DeleteDataView: View {
    @EnvironmentObject private var session: SessionManager
    @Environment(\.dismiss) private var dismiss
    @State private var confirming = false
    @State private var working = false

    var body: some View {
        List {
            Section {
                Text("Squadstream has no account. What it stores is one row for this device: your name, a scrambled version of your phone number so contacts can find you, and your last known position.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textDim)
            }
            Section {
                Button(role: .destructive) { confirming = true } label: {
                    if working { ProgressView() } else { Text("Delete everything") }
                }
                .disabled(working)
            } footer: {
                Text("This removes that row and every squad membership tied to it. It cannot be undone.")
            }
        }
        .navigationTitle("Your data")
        .confirmationDialog("Delete everything?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                working = true
                Task {
                    await session.deleteMyData()
                    working = false
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) { }
        }
    }
}
