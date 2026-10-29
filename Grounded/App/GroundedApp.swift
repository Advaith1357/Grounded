//
//  GroundedApp.swift
//  Grounded
//
//  Entry point. Creates the real ScreenTimeShieldManager, injects it into the
//  single view model (alongside the real GeminiService and TaskStore) and into
//  the environment so the Queue's block lists can use it. Shows onboarding until
//  it's finished; permissions are asked for there, with context, not at launch.
//  In the Screen Time build it re-applies the shield and schedules the Circuit
//  Breaker in the background.
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
    @AppStorage(SettingsKey.onboardingCompleted) private var onboardingCompleted = false

    init() {
        UNUserNotificationCenter.current().delegate = ForegroundNotificationPresenter.shared
        let shield = ScreenTimeShieldManager()
        _shieldManager = StateObject(wrappedValue: shield)
        _viewModel = StateObject(wrappedValue: GroundedViewModel(shield: shield, notifier: LocalGroundingNotifier.shared))
        _friends = StateObject(wrappedValue: FriendsViewModel(service: FriendsService(baseURL: {
            UserDefaults.standard.string(forKey: SettingsKey.friendsServerURL) ?? SettingsKey.defaultFriendsServerURL
        })))
    }

    /// Re-applies the shield at launch if Screen Time access is already approved.
    /// Nothing is asked for here: onboarding (or the Queue's button) asks, with
    /// context, instead of a permission prompt appearing out of nowhere.
    private func restoreScreenTimeIfApproved() {
        guard ScreenTimeSupport.isEnabled else { return }
        shieldManager.refreshAccess()
        if shieldManager.accessApproved { shieldManager.reapply() }
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
                        shieldManager.refreshAccess()
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
                    restoreScreenTimeIfApproved()
                }
                .fullScreenCover(isPresented: Binding(get: { !onboardingCompleted }, set: { _ in })) {
                    OnboardingView { onboardingCompleted = true }
                        .environmentObject(shieldManager)
                        .environmentObject(friends)
                }
        }
    }
}
