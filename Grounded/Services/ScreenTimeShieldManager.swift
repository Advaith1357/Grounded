//
//  ScreenTimeShieldManager.swift
//  Grounded
//
//  The real shield: applies Apple's Screen Time restrictions to whatever apps
//  the user picked in the Kernel sheet. `.grounded` shields the selection,
//  `.unlocked` clears the shield. Requires the Family Controls entitlement
//  (see project.yml) and an authorized session (see GroundedApp).
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

    /// The apps / categories / websites to restrict. Persisted (to the App
    /// Group, so the extension can read it) on every change; editing it while
    /// grounded re-applies the shield immediately.
    @Published var selection: FamilyActivitySelection {
        didSet {
            SharedSelection.save(selection)
            if state == .grounded { apply() }
        }
    }

    private let store = ManagedSettingsStore()
    private let center = DeviceActivityCenter()

    // Schedules requested before authorization are remembered and re-pushed
    // by `reapply()`; startMonitoring throws until the user approves.
    private var pendingReGround: Date?
    private var pendingLockout: NightlyLockout?

    init() {
        selection = SharedSelection.load()
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

    private func apply() {
        ShieldApplier.apply(state, selection: selection, to: store)
    }

    private func startBreakMonitoring(endingAt date: Date) {
        let window = ShieldSchedule.breakWindow(endingAt: date)
        let schedule = DeviceActivitySchedule(intervalStart: window.start, intervalEnd: window.end, repeats: false)
        do {
            try center.startMonitoring(.breakEnd, during: schedule)
        } catch {
            print("[ScreenTimeShieldManager] couldn't schedule break end: \(error)")
        }
    }

    private func startLockoutMonitoring(_ lockout: NightlyLockout) {
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
