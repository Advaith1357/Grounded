//
//  GridView.swift
//  Grounded
//
//  "The Grid" tab — social accountability. Join with a display name, share
//  your friend code, add friends by theirs, see who is grounded or on a
//  break, and nudge them with the Zap button. Backed by the friends server
//  (see FriendsViewModel); all state lives there, not in this view.
//

import SwiftUI

struct GridView: View {
    @EnvironmentObject private var friends: FriendsViewModel

    @State private var nameInput = ""
    @State private var codeInput = ""
    @State private var showLeaveConfirm = false
    @State private var copiedCode = false

    private static let codeLength = 6
    private static let maxNameLength = 24

    var body: some View {
        NavigationStack {
            ZStack {
                NexusColor.background.ignoresSafeArea()
                CircuitBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        if let message = friends.errorMessage { errorBanner(message) }

                        if let profile = friends.profile {
                            codeCard(profile)
                            addFriendRow
                            friendsList
                        } else {
                            joinCard
                        }
                    }
                    .padding(NexusMetrics.screenPadding)
                }
                .scrollDismissesKeyboard(.interactively)
                .refreshable { await friends.refresh() }
            }
            .navigationTitle("The Grid")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { friends.setFastPolling(true) }
            .onDisappear { friends.setFastPolling(false) }
            .toolbar {
                if friends.isJoined {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Refresh") { Task { await friends.refresh() } }
                            Button("Leave The Grid", role: .destructive) { showLeaveConfirm = true }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .tint(NexusColor.accent)
                    }
                }
            }
            .confirmationDialog(
                "Leave The Grid?",
                isPresented: $showLeaveConfirm,
                titleVisibility: .visible
            ) {
                Button("Leave and delete my account", role: .destructive) { Task { await friends.leave() } }
                Button("Stay", role: .cancel) { }
            } message: {
                Text("Your friend code stops working and your friends lose you from their list.")
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SOCIAL ACCOUNTABILITY")
                .font(NexusFont.mono(11))
                .foregroundStyle(NexusColor.accent)
            Text("See who's grounded and nudge friends on a break.")
                .font(NexusFont.sans(13))
                .foregroundStyle(NexusColor.textSecondary)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(hex: 0xEF4444))
            Text(message)
                .font(NexusFont.sans(13))
                .foregroundStyle(NexusColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                friends.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(NexusColor.textSecondary)
            }
        }
        .padding(14)
        .background(NexusColor.surface)
        .overlay(RoundedRectangle(cornerRadius: NexusMetrics.cardRadius).stroke(Color(hex: 0xEF4444).opacity(0.6)))
        .clipShape(RoundedRectangle(cornerRadius: NexusMetrics.cardRadius))
    }

    // MARK: - Joining

    private var joinCard: some View {
        NexusCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("JOIN THE GRID")
                    .font(NexusFont.mono(12))
                    .foregroundStyle(NexusColor.textSecondary)
                Text("Pick a name your friends will see. You'll get a friend code to share.")
                    .font(NexusFont.sans(13))
                    .foregroundStyle(NexusColor.textSecondary)

                TextField("Display name", text: $nameInput)
                    .font(NexusFont.mono(16))
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.join)
                    .onSubmit(join)
                    .onChange(of: nameInput) { _, value in
                        if value.count > Self.maxNameLength { nameInput = String(value.prefix(Self.maxNameLength)) }
                    }
                    .padding(12)
                    .background(NexusColor.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: NexusMetrics.chipRadius))

                NexusPrimaryButton(
                    title: friends.isBusy ? "JOINING…" : "JOIN",
                    isEnabled: !friends.isBusy && !nameInput.trimmingCharacters(in: .whitespaces).isEmpty,
                    action: join
                )
            }
        }
    }

    private func join() {
        Task { await friends.join(name: nameInput) }
    }

    // MARK: - Your code + adding friends

    private func codeCard(_ profile: FriendsProfile) -> some View {
        NexusCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("YOUR FRIEND CODE")
                    .font(NexusFont.mono(12))
                    .foregroundStyle(NexusColor.textSecondary)
                Text(profile.code)
                    .font(.system(size: 34, weight: .heavy, design: .monospaced))
                    .tracking(4)
                    .foregroundStyle(NexusColor.accent)
                    .textSelection(.enabled)

                HStack(spacing: 10) {
                    Button {
                        UIPasteboard.general.string = profile.code
                        copiedCode = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copiedCode = false
                        }
                    } label: {
                        Label(copiedCode ? "Copied" : "Copy", systemImage: copiedCode ? "checkmark" : "doc.on.doc")
                            .font(NexusFont.mono(12, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(NexusColor.accent)

                    ShareLink(item: "Add me on Grounded — my friend code is \(profile.code)") {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(NexusFont.mono(12, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(NexusColor.accent)
                }

                Text("Signed in as \(profile.name)")
                    .font(NexusFont.sans(11))
                    .foregroundStyle(NexusColor.textSecondary)
            }
        }
    }

    private var addFriendRow: some View {
        HStack(spacing: 10) {
            TextField("Friend's code", text: $codeInput)
                .font(NexusFont.mono(16))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(addFriend)
                .onChange(of: codeInput) { _, value in
                    let cleaned = String(value.uppercased().filter { !$0.isWhitespace }.prefix(Self.codeLength))
                    if cleaned != value { codeInput = cleaned }
                }
                .padding(12)
                .background(NexusColor.surface)
                .overlay(RoundedRectangle(cornerRadius: NexusMetrics.chipRadius).stroke(NexusColor.border))
                .clipShape(RoundedRectangle(cornerRadius: NexusMetrics.chipRadius))

            Button(action: addFriend) {
                Text("ADD")
                    .font(NexusFont.mono(14, weight: .bold))
                    .foregroundStyle(NexusColor.background)
                    .padding(.horizontal, 20)
                    .frame(height: 46)
                    .background(NexusColor.accent)
                    .clipShape(Capsule())
            }
            .disabled(codeInput.count != Self.codeLength || friends.isBusy)
            .opacity(codeInput.count == Self.codeLength && !friends.isBusy ? 1 : 0.4)
        }
    }

    private func addFriend() {
        guard codeInput.count == Self.codeLength else { return }
        Task {
            if await friends.addFriend(code: codeInput) { codeInput = "" }
        }
    }

    // MARK: - Friends list

    @ViewBuilder
    private var friendsList: some View {
        if friends.friends.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "person.2")
                    .font(.system(size: 32))
                    .foregroundStyle(NexusColor.textSecondary)
                Text("No friends yet")
                    .font(NexusFont.sans(16, weight: .bold))
                    .foregroundStyle(NexusColor.textPrimary)
                Text("Share your code, or enter a friend's above.")
                    .font(NexusFont.sans(13))
                    .foregroundStyle(NexusColor.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
        } else {
            // Re-evaluated periodically so a break that expires while this
            // screen is open flips the friend back to grounded.
            TimelineView(.periodic(from: .now, by: 5)) { timeline in
                VStack(spacing: 10) {
                    ForEach(friends.friends) { friend in
                        friendRow(friend, now: timeline.date)
                    }
                }
            }
        }
    }

    private func friendRow(_ friend: Friend, now: Date) -> some View {
        let isGrounded = friend.effectiveState(at: now) == .grounded
        let ringColor = isGrounded ? NexusColor.accent : NexusColor.textSecondary
        let isNudged = friends.nudgeCooldowns.contains(friend.id)

        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(NexusColor.surfaceElevated)
                    .frame(width: 48, height: 48)
                Circle()
                    .stroke(ringColor, lineWidth: 2)
                    .frame(width: 48, height: 48)
                Text(String(friend.name.prefix(1)).uppercased())
                    .font(NexusFont.sans(18, weight: .bold))
                    .foregroundStyle(NexusColor.textPrimary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(friend.name)
                    .font(NexusFont.sans(16, weight: .bold))
                    .foregroundStyle(NexusColor.textPrimary)
                    .lineLimit(1)
                Text(isGrounded ? "[ GROUNDED ]" : "[ ON A BREAK ]")
                    .font(NexusFont.mono(11))
                    .foregroundStyle(isGrounded ? NexusColor.accent : NexusColor.textSecondary)
            }

            Spacer()

            Button {
                Task { await friends.nudge(friend) }
            } label: {
                Image(systemName: isNudged ? "checkmark" : "bolt.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(NexusColor.background)
                    .frame(width: 36, height: 36)
                    .background(isNudged ? NexusColor.textSecondary : NexusColor.accent)
                    .clipShape(Circle())
            }
            .disabled(isNudged)
            .accessibilityLabel("Nudge \(friend.name)")
        }
        .padding(14)
        .background(NexusColor.surface)
        .overlay(RoundedRectangle(cornerRadius: NexusMetrics.cardRadius).stroke(NexusColor.border))
        .clipShape(RoundedRectangle(cornerRadius: NexusMetrics.cardRadius))
        .contextMenu {
            Button("Remove friend", role: .destructive) { Task { await friends.remove(friend) } }
        }
    }
}

#if DEBUG
#Preview("Joined") {
    GridView().environmentObject(FriendsViewModel.preview())
}

#Preview("Not joined") {
    GridView().environmentObject(FriendsViewModel.preview(joined: false))
}
#endif
