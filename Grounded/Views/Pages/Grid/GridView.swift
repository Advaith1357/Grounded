//
//  GridView.swift
//  Grounded
//
//  "The Grid" tab — a social-accountability friends list, NOT an analytics
//  screen (that content moved to Insights). Mock data only: there's no
//  backend, no friend-request flow, no real presence — just static sample
//  rows and a "nudge" button that logs to the console and gives brief visual
//  confirmation, the same mocked-backend spirit as MockShieldManager.
//

import SwiftUI

private enum FriendStatus {
    case grounded
    case onBreak
}

private struct MockFriend: Identifiable {
    let id = UUID()
    let name: String
    let status: FriendStatus
}

private let mockFriends: [MockFriend] = [
    MockFriend(name: "Alex", status: .grounded),
    MockFriend(name: "Jordan", status: .onBreak),
    MockFriend(name: "Sam", status: .grounded),
    MockFriend(name: "Riley", status: .onBreak),
    MockFriend(name: "Casey", status: .grounded),
]

struct GridView: View {
    @State private var nudgedFriendIDs: Set<UUID> = []

    var body: some View {
        NavigationStack {
            ZStack {
                NexusColor.background.ignoresSafeArea()
                CircuitBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        VStack(spacing: 10) {
                            ForEach(mockFriends) { friend in
                                friendRow(friend)
                            }
                        }
                    }
                    .padding(NexusMetrics.screenPadding)
                }
            }
            .navigationTitle("The Grid")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

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

    private func friendRow(_ friend: MockFriend) -> some View {
        let isGrounded = friend.status == .grounded
        let ringColor = isGrounded ? NexusColor.accent : NexusColor.textSecondary
        let isNudged = nudgedFriendIDs.contains(friend.id)

        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(NexusColor.surfaceElevated)
                    .frame(width: 48, height: 48)
                Circle()
                    .stroke(ringColor, lineWidth: 2)
                    .frame(width: 48, height: 48)
                Text(String(friend.name.prefix(1)))
                    .font(NexusFont.sans(18, weight: .bold))
                    .foregroundStyle(NexusColor.textPrimary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(friend.name)
                    .font(NexusFont.sans(16, weight: .bold))
                    .foregroundStyle(NexusColor.textPrimary)
                Text(isGrounded ? "[ GROUNDED ]" : "[ ON A BREAK ]")
                    .font(NexusFont.mono(11))
                    .foregroundStyle(isGrounded ? NexusColor.accent : NexusColor.textSecondary)
            }

            Spacer()

            Button {
                sendNudge(to: friend)
            } label: {
                Image(systemName: isNudged ? "checkmark" : "bolt.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(NexusColor.background)
                    .frame(width: 36, height: 36)
                    .background(isNudged ? NexusColor.textSecondary : NexusColor.accent)
                    .clipShape(Circle())
            }
            .disabled(isNudged)
        }
        .padding(14)
        .background(NexusColor.surface)
        .overlay(RoundedRectangle(cornerRadius: NexusMetrics.cardRadius).stroke(NexusColor.border))
        .clipShape(RoundedRectangle(cornerRadius: NexusMetrics.cardRadius))
    }

    private func sendNudge(to friend: MockFriend) {
        print("[GridView] Nudge sent to \(friend.name)")
        nudgedFriendIDs.insert(friend.id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            nudgedFriendIDs.remove(friend.id)
        }
    }
}

#if DEBUG
#Preview {
    GridView()
}
#endif
