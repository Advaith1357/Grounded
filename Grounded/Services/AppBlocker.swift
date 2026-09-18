//
//  AppBlocker.swift
//  Grounded
//
//  ============================================================================
//  STUB BOUNDARY — real app blocking is intentionally NOT implemented here.
//  ============================================================================
//
//  Real blocking requires Apple's Family Controls entitlement (FamilyControls /
//  ManagedSettings / DeviceActivity). That entitlement is unavailable on a free
//  Personal Team, so this build ships `MockAppBlocker`, which only flips a flag
//  and logs.
//
//  When the entitlement is available, add a `ScreenTimeBlocker` that conforms to
//  this SAME `AppBlocker` protocol and inject it in `GroundedApp` instead of
//  `MockAppBlocker`. Nothing outside this file should need to change:
//    - the view model talks only to `AppBlocker`
//    - the UI observes `GroundedViewModel.isBlocking`
//
//  Do NOT `import FamilyControls`, `ManagedSettings`, or `DeviceActivity` in
//  this build.
//  ============================================================================

import Foundation
import Combine

protocol AppBlocker: AnyObject {
    var isBlocking: Bool { get }
    var blockedAppNames: [String] { get set }
    func block()
    func unblock()
}

/// Simulated blocker. Flips `isBlocking` and prints; no system side effects.
final class MockAppBlocker: ObservableObject, AppBlocker {

    @Published private(set) var isBlocking: Bool = false

    /// Free-text app names the user typed. A real blocker would map these to
    /// `ApplicationToken`s via the system picker.
    @Published var blockedAppNames: [String] = []

    func block() {
        isBlocking = true
        print("[MockAppBlocker] block() — pretending to block \(describeTargets()). Real blocking needs Family Controls.")
    }

    func unblock() {
        isBlocking = false
        print("[MockAppBlocker] unblock() — apps 'unblocked'.")
    }

    private func describeTargets() -> String {
        blockedAppNames.isEmpty ? "(no apps named)" : blockedAppNames.joined(separator: ", ")
    }
}
