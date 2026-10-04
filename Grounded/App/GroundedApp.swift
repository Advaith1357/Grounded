//
//  GroundedApp.swift
//  Grounded
//
//  Entry point. Creates the real ScreenTimeShieldManager, injects it into the
//  single view model (alongside the real GeminiService and TaskStore) and into
//  the environment so the Kernel sheet can bind to its app selection. On launch
//  it asks for Screen Time authorization (and for notification permission, used
//  by the shield's "Go to Grounded" button) and schedules the Circuit Breaker.
//  Also owns the friends view model: it polls the friends server while the app
//  is in the foreground and pushes this device's shield state on every change.
//

import SwiftUI
import FamilyControls
import UserNotifications

@main
struct GroundedApp: App {
    @StateObject private var shieldManager: ScreenTimeShieldManager
    @StateObject private var viewModel: GroundedViewModel
    @StateObject private var friends: FriendsViewModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let shield = ScreenTimeShieldManager()
        _shieldManager = StateObject(wrappedValue: shield)
        _viewModel = StateObject(wrappedValue: GroundedViewModel(shield: shield))
        _friends = StateObject(wrappedValue: FriendsViewModel(service: FriendsService(baseURL: {
            UserDefaults.standard.string(forKey: SettingsKey.friendsServerURL) ?? SettingsKey.defaultFriendsServerURL
        })))
    }

    private func pushFriendStatus() async {
        await friends.pushStatus(viewModel.shieldState, unlockEndsAt: viewModel.economy.unlockEndsAt)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(viewModel: viewModel)
                .environmentObject(shieldManager)
                .environmentObject(friends)
                .task {
                    friends.startPolling()
                    await pushFriendStatus()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        friends.startPolling()
                        Task { await pushFriendStatus() }
                    } else {
                        friends.stopPolling()
                    }
                }
                .onChange(of: viewModel.shieldState) { _, _ in
                    Task { await pushFriendStatus() }
                }
                .task {
                    shieldManager.scheduleNightlyLockout(NightlyLockout.current)
                    _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                    do {
                        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                        // Anything applied before approval had no effect.
                        shieldManager.reapply()
                    } catch {
                        print("[GroundedApp] Screen Time authorization failed: \(error)")
                    }
                }
        }
    }
}
