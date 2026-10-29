//
//  FriendsViewModel.swift
//  Grounded
//
//  The social layer: identity on the friends server, the friends list with
//  live shield status, nudges in both directions. Separate from
//  GroundedViewModel on purpose — the focus loop never depends on the network.
//
//  Updates arrive by polling while the app is in the foreground. Pushing a
//  nudge to a closed app would need APNs (a paid developer account), so
//  nudges are delivered the next time the recipient opens Grounded.
//

import Foundation
import SwiftUI
import UIKit

@MainActor
final class FriendsViewModel: ObservableObject {

    @Published private(set) var profile: FriendsProfile?
    @Published private(set) var friends: [Friend] = []
    /// Nudges received and not yet dismissed; the root view shows a banner.
    @Published private(set) var incomingNudges: [Nudge] = []
    /// IDs of friends nudged recently — their Zap button is disabled.
    @Published private(set) var nudgeCooldowns: Set<String> = []
    @Published private(set) var isBusy = false
    /// Last problem worth showing (offline, bad code, ...). Cleared by the UI.
    @Published var errorMessage: String?

    private let service: FriendsProviding
    private let defaults: UserDefaults
    private var token: String?

    private var pollTask: Task<Void, Never>?
    private var seenNudgeIDs: Set<Int> = []
    private var statusToPush: (state: FriendState, endsAt: Date?)?
    private var statusIsStale = false

    private static let profileKey = "friends.profile"
    /// Quick while the Grid tab is on screen; slow elsewhere (nudges still
    /// arrive, just a little later) so a free host isn't hit needlessly.
    private static let fastPollInterval: Duration = .seconds(8)
    private static let slowPollInterval: Duration = .seconds(30)
    private var pollInterval = FriendsViewModel.slowPollInterval

    // MARK: - Init

    init(service: FriendsProviding, defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults

        if let data = defaults.data(forKey: Self.profileKey),
           let saved = try? JSONDecoder().decode(FriendsProfile.self, from: data),
           let savedToken = KeychainStore.loadFriendsToken() {
            profile = saved
            token = savedToken
        }
    }

    var isJoined: Bool { profile != nil }

    // MARK: - Identity

    func join(name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let registration = try await service.register(name: trimmed)
            token = registration.token
            profile = registration.profile
            KeychainStore.saveFriendsToken(registration.token)
            defaults.set(try? JSONEncoder().encode(registration.profile), forKey: Self.profileKey)
            errorMessage = nil
            statusIsStale = true
            await refresh()
        } catch {
            report(error)
        }
    }

    /// Deletes the server account and forgets the local identity.
    func leave() async {
        if let token { try? await service.deleteAccount(token: token) }
        clearIdentity()
    }

    private func clearIdentity() {
        token = nil
        profile = nil
        friends = []
        incomingNudges = []
        nudgeCooldowns = []
        seenNudgeIDs = []
        KeychainStore.deleteFriendsToken()
        defaults.removeObject(forKey: Self.profileKey)
    }

    // MARK: - Friends

    func addFriend(code: String) async -> Bool {
        guard let token, !isBusy else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await service.addFriend(code: code, token: token)
            errorMessage = nil
            await refresh()
            return true
        } catch {
            report(error)
            return false
        }
    }

    func remove(_ friend: Friend) async {
        guard let token else { return }
        do {
            try await service.removeFriend(id: friend.id, token: token)
            friends.removeAll { $0.id == friend.id }
        } catch {
            report(error)
        }
    }

    func nudge(_ friend: Friend) async {
        guard let token, !nudgeCooldowns.contains(friend.id) else { return }
        do {
            try await service.sendNudge(to: friend.id, token: token)
            errorMessage = nil
            startCooldown(for: friend.id, seconds: 60)
        } catch FriendsError.rateLimited(let retryAfter) {
            startCooldown(for: friend.id, seconds: retryAfter)
        } catch {
            report(error)
        }
    }

    private func startCooldown(for friendID: String, seconds: TimeInterval) {
        nudgeCooldowns.insert(friendID)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            self?.nudgeCooldowns.remove(friendID)
        }
    }

    func dismiss(_ nudge: Nudge) {
        incomingNudges.removeAll { $0.id == nudge.id }
    }

    // MARK: - Status + sync

    /// Reports this device's shield state to friends. Remembered and retried
    /// on the next poll if the server can't be reached.
    func pushStatus(_ shield: ShieldState, unlockEndsAt: Date?) async {
        let state: FriendState = shield == .unlocked ? .unlocked : .grounded
        statusToPush = (state, state == .unlocked ? unlockEndsAt : nil)
        statusIsStale = true
        await flushStatus()
    }

    private func flushStatus() async {
        guard statusIsStale, let token, let status = statusToPush else { return }
        do {
            try await service.updateStatus(status.state, unlockEndsAt: status.endsAt, token: token)
            statusIsStale = false
        } catch FriendsError.unauthorized {
            handleUnauthorized()
        } catch {
            // Offline: stays stale and is retried by the next refresh.
        }
    }

    /// Fetches friends and incoming nudges. Quiet on failure when `silent`
    /// (background polls shouldn't nag).
    func refresh(silent: Bool = false) async {
        guard let token else { return }
        await flushStatus()
        guard self.token != nil else { return }
        do {
            let result = try await service.sync(token: token)
            friends = result.friends
            receive(result.nudges, token: token)
            if !silent { errorMessage = nil }
        } catch FriendsError.unauthorized {
            handleUnauthorized()
        } catch is CancellationError {
        } catch {
            if !silent { report(error) }
        }
    }

    private func receive(_ nudges: [Nudge], token: String) {
        let fresh = nudges.filter { !seenNudgeIDs.contains($0.id) }
        guard !fresh.isEmpty else { return }
        seenNudgeIDs.formUnion(fresh.map(\.id))
        incomingNudges.append(contentsOf: fresh)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task { [service] in
            try? await service.acknowledgeNudges(ids: fresh.map(\.id), token: token)
        }
    }

    // MARK: - Polling

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh(silent: true)
                guard let interval = self?.pollInterval else { return }
                try? await Task.sleep(for: interval)
            }
        }
    }

    /// The Grid tab calls this as it appears/disappears. Speeding up refreshes
    /// immediately so the list is current the moment the tab opens.
    func setFastPolling(_ fast: Bool) {
        pollInterval = fast ? Self.fastPollInterval : Self.slowPollInterval
        guard fast, pollTask != nil, isJoined else { return }
        stopPolling()
        startPolling()
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Connection check

    /// For the Settings "Test connection" button: a plain-language result.
    func testConnection() async -> (ok: Bool, message: String) {
        do {
            try await service.ping()
            return (true, "Connected.")
        } catch {
            return (false, (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    // MARK: - Errors

    private func handleUnauthorized() {
        clearIdentity()
        errorMessage = FriendsError.unauthorized.errorDescription
    }

    private func report(_ error: Error) {
        if error is CancellationError { return }
        if case FriendsError.unauthorized = error { return handleUnauthorized() }
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

// MARK: - Preview fixtures

#if DEBUG
extension FriendsViewModel {

    /// A joined user with a few friends, backed by a service that never touches the network.
    static func preview(joined: Bool = true) -> FriendsViewModel {
        let viewModel = FriendsViewModel(service: PreviewFriendsService(), defaults: UserDefaults(suiteName: "preview.friends") ?? .standard)
        if joined {
            viewModel.profile = FriendsProfile(id: "me", name: "You", code: "K7M2QX")
            viewModel.token = "preview"
            viewModel.friends = [
                Friend(id: "1", name: "Alex", state: .grounded, unlockEndsAt: nil, statusUpdatedAt: Date()),
                Friend(id: "2", name: "Jordan", state: .unlocked, unlockEndsAt: Date().addingTimeInterval(900), statusUpdatedAt: Date()),
            ]
        }
        return viewModel
    }
}

private struct PreviewFriendsService: FriendsProviding {
    func register(name: String) async throws -> Registration {
        Registration(profile: FriendsProfile(id: "me", name: name, code: "K7M2QX"), token: "preview")
    }
    func deleteAccount(token: String) async throws {}
    func updateStatus(_ state: FriendState, unlockEndsAt: Date?, token: String) async throws {}
    func sync(token: String) async throws -> SyncResult { SyncResult(friends: [], nudges: []) }
    func ping() async throws {}
    func addFriend(code: String, token: String) async throws -> Friend {
        Friend(id: "x", name: "New", state: .grounded, unlockEndsAt: nil, statusUpdatedAt: Date())
    }
    func removeFriend(id: String, token: String) async throws {}
    func sendNudge(to friendID: String, token: String) async throws {}
    func acknowledgeNudges(ids: [Int], token: String) async throws {}
}
#endif
