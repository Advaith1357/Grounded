//
//  ShieldManager.swift
//  Grounded
//
//  The shield abstraction. `ScreenTimeShieldManager` is the real implementation
//  (FamilyControls / ManagedSettings / DeviceActivity); `MockShieldManager`
//  below only exists for SwiftUI previews and test fixtures, where the Screen
//  Time frameworks can't run. The view model and every view talk only to
//  `ShieldManager` / `GroundedViewModel.shieldState`. `ShieldState` itself
//  lives in Shared/ so the DeviceActivityMonitor extension can use it too.
//

import Foundation
import Combine

protocol ShieldManager: AnyObject {
    var state: ShieldState { get }
    func ground()
    func unlock()

    /// Asks the OS to re-ground at `date` even if the app is no longer
    /// running (a Discharge break expiring while the app is killed).
    func scheduleReGround(at date: Date)
    func cancelScheduledReGround()
}

/// Preview/test-only shield. Flips `state` and prints; no system side effects.
final class MockShieldManager: ObservableObject, ShieldManager {

    @Published private(set) var state: ShieldState = .grounded

    func ground() {
        state = .grounded
        print("[MockShieldManager] state -> .grounded")
    }

    func unlock() {
        state = .unlocked
        print("[MockShieldManager] state -> .unlocked")
    }

    func scheduleReGround(at date: Date) {
        print("[MockShieldManager] scheduleReGround(at: \(date))")
    }

    func cancelScheduledReGround() {
        print("[MockShieldManager] cancelScheduledReGround()")
    }
}
