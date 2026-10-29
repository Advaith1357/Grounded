//
//  ScreenTimeShieldManager.swift
//  Grounded
//
//  The real shield: applies Apple's Screen Time restrictions to the apps in the
//  block lists that are switched on (managed from the Queue tab). `.grounded`
//  shields them, `.unlocked` clears the shield. A shielded app is only
//  intercepted when it's opened; nothing else on the phone is touched.
//
//  Active only in the Screen Time build (see ScreenTimeSupport): it needs the
//  Family Controls entitlement (project.screentime.yml) and an authorized
//  session (see GroundedApp). In the default build every system call below is
//  skipped and the lists are just saved.
//
//  The ManagedSettingsStore lives in the OS, not in this process, so a shield
//  keeps applying even if the app is killed. Two DeviceActivity schedules
//  cover the cases where nothing in the app is running to re-ground:
//    .breakEnd       a one-off window ending when the current break is due
//    .circuitBreaker a repeating nightly window (see NightlyLockout)
//  The DeviceActivityMonitor extension reacts to both.
//

import Foundation
import Combine
import FamilyControls
import ManagedSettings
import DeviceActivity

final class ScreenTimeShieldManager: ObservableObject, ShieldManager {

    @Published private(set) var state: ShieldState = .grounded

    /// Whether Screen Time access is approved right now. Published so the Queue
    /// can show a "turn it on" button after a "Don't Allow", since iOS won't
    /// raise the prompt again on its own.
    @Published private(set) var accessApproved = false

    /// The user's block lists. Persisted (to the App Group, so the extension
    /// can read them) on every change. The shield is re-applied immediately,
    /// but only when what's actually blocked changes: renaming a list or
    /// toggling an empty one doesn't touch the system.
    @Published var blockLists: [BlockList] {
        didSet {
            SharedBlockLists.save(blockLists)
            guard state == .grounded else { return }
            if BlockLists.combinedSelection(of: oldValue) != BlockLists.combinedSelection(of: blockLists) {
                apply()
            }
        }
    }

    // Lazy so a build without the entitlement never even creates them.
    private lazy var store = ManagedSettingsStore()
    private lazy var center = DeviceActivityCenter()

    // Schedules requested before authorization are remembered and re-pushed
    // by `reapply()`; startMonitoring throws until the user approves.
    private var pendingReGround: Date?
    private var pendingLockout: NightlyLockout?

    init() {
        blockLists = SharedBlockLists.load() ?? []
    }

    @MainActor
    func refreshAccess() {
        let approved = ScreenTimeSupport.isEnabled && AuthorizationCenter.shared.authorizationStatus == .approved
        if approved != accessApproved { accessApproved = approved }
    }

    /// Asks for Screen Time access. Called at first launch and from the
    /// Queue's button; safe to call again after a "Don't Allow".
    @MainActor
    func requestAccess() async {
        guard ScreenTimeSupport.isEnabled else { return }
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        } catch {
            print("[ScreenTimeShieldManager] Screen Time authorization failed: \(error)")
        }
        refreshAccess()
        if accessApproved { reapply() }
    }

    /// Adds an empty, switched-on list and returns its id.
    @discardableResult
    func addBlockList(named name: String) -> UUID {
        let list = BlockList(name: name)
        blockLists.append(list)
        return list.id
    }

    func removeBlockList(id: UUID) {
        blockLists.removeAll { $0.id == id }
    }

    func blockList(id: UUID) -> BlockList? {
        blockLists.first { $0.id == id }
    }

    /// Edits a list by id. A no-op if it's gone, so views bound to a list that
    /// was just deleted can't index past the end of the array while SwiftUI
    /// finishes tearing them down.
    func updateBlockList(id: UUID, _ change: (inout BlockList) -> Void) {
        guard let index = blockLists.firstIndex(where: { $0.id == id }) else { return }
        change(&blockLists[index])
    }

    func ground() {
        state = .grounded
        apply()
    }

    func unlock() {
        state = .unlocked
        apply()
    }

    func scheduleReGround(at date: Date) {
        pendingReGround = date
        startBreakMonitoring(endingAt: date)
    }

    func cancelScheduledReGround() {
        pendingReGround = nil
        guard ScreenTimeSupport.isEnabled else { return }
        center.stopMonitoring([.breakEnd])
    }

    func scheduleNightlyLockout(_ lockout: NightlyLockout) {
        pendingLockout = lockout
        startLockoutMonitoring(lockout)
    }

    /// Re-pushes the current state and schedules to the OS. Call after
    /// authorization is granted: anything applied before that had no effect.
    func reapply() {
        apply()
        if let date = pendingReGround {
            if date > Date() { startBreakMonitoring(endingAt: date) } else { pendingReGround = nil }
        }
        if let lockout = pendingLockout { startLockoutMonitoring(lockout) }
    }

    /// Only touches the system in the Screen Time build, and only once access
    /// is approved. Before that there's nothing to apply, and the lists are
    /// still saved. `reapply()` runs again the moment access is granted.
    private func apply() {
        guard ScreenTimeSupport.isEnabled,
              AuthorizationCenter.shared.authorizationStatus == .approved else { return }
        ShieldApplier.apply(state, lists: blockLists, to: store)
    }

    private func startBreakMonitoring(endingAt date: Date) {
        guard ScreenTimeSupport.isEnabled else { return }
        let window = ShieldSchedule.breakWindow(endingAt: date)
        let schedule = DeviceActivitySchedule(intervalStart: window.start, intervalEnd: window.end, repeats: false)
        do {
            try center.startMonitoring(.breakEnd, during: schedule)
        } catch {
            print("[ScreenTimeShieldManager] couldn't schedule break end: \(error)")
        }
    }

    private func startLockoutMonitoring(_ lockout: NightlyLockout) {
        guard ScreenTimeSupport.isEnabled else { return }
        guard lockout.canBeScheduledInBackground else {
            center.stopMonitoring([.circuitBreaker])
            return
        }
        let schedule = DeviceActivitySchedule(
            intervalStart: lockout.startComponents,
            intervalEnd: lockout.endComponents,
            repeats: true
        )
        do {
            try center.startMonitoring(.circuitBreaker, during: schedule)
        } catch {
            print("[ScreenTimeShieldManager] couldn't schedule Circuit Breaker: \(error)")
        }
    }
}
