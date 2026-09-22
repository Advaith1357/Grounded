//
//  ShieldManager.swift
//  Grounded
//
//  ============================================================================
//  STUB BOUNDARY — real screen-time enforcement is intentionally NOT
//  implemented here.
//  ============================================================================
//
//  Real enforcement requires Apple's Family Controls entitlement
//  (FamilyControls / ManagedSettings / DeviceActivity), which needs a paid
//  Apple Developer account. That $100/year fee is explicitly deferred for now,
//  so this build must never import any of those three frameworks and never add
//  the Family Controls capability. `MockShieldManager` just flips `state` and
//  logs to the console — good enough to drive every other feature (queue,
//  economy, Gemini verification) in the Simulator.
//
//  When the entitlement is available: add a `ScreenTimeShieldManager` that
//  conforms to this same `ShieldManager` protocol and inject it in
//  `GroundedApp` instead of `MockShieldManager`. Nothing outside this file
//  should need to change — the view model and every view talk only to
//  `ShieldManager` / `GroundedViewModel.shieldState`.
//
//  Do NOT `import FamilyControls`, `ManagedSettings`, or `DeviceActivity` in
//  this build.
//  ============================================================================

import Foundation
import Combine

/// The device's screen-time state. `.grounded` is the default/rest state
/// (apps restricted); `.unlocked` is a spent-Voltage break.
enum ShieldState: String {
    case grounded
    case unlocked
}

protocol ShieldManager: AnyObject {
    var state: ShieldState { get }
    func ground()
    func unlock()
}

/// Simulated shield. Flips `state` and prints; no system side effects.
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
}
