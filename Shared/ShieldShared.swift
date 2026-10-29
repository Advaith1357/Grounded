//
//  ShieldShared.swift
//  Shared by the app and the DeviceActivityMonitor extension.
//
//  The extension can't see the app's memory or sandbox, so everything it needs
//  to re-apply the shield travels through the App Group: the block lists
//  (see BlockLists.swift, encoded in the group's UserDefaults) and the
//  ManagedSettingsStore, which iOS shares between an app and its extensions.
//

import Foundation
import FamilyControls
import ManagedSettings
import DeviceActivity

/// The device's screen-time state. `.grounded` is the default/rest state
/// (apps restricted); `.unlocked` is a spent-Voltage break.
enum ShieldState: String {
    case grounded
    case unlocked
}

enum AppGroup {
    /// Derived from the app's bundle ID rather than hard-coded: App Group IDs
    /// are unique across every developer on Apple's platform, so a generic one
    /// would likely already be taken. The extensions' bundle IDs are the app's
    /// plus a suffix, so they strip it and arrive at the same group.
    static let identifier = identifier(
        forBundleID: Bundle.main.bundleIdentifier,
        isExtension: Bundle.main.bundlePath.hasSuffix(".appex")
    )

    static func identifier(forBundleID bundleID: String?, isExtension: Bool) -> String {
        guard var id = bundleID, !id.isEmpty else { return "group.com.grounded.app" }
        if isExtension, let lastDot = id.lastIndex(of: ".") {
            id = String(id[..<lastDot])
        }
        return "group.\(id)"
    }

    /// The group's defaults, or standard defaults when the group isn't
    /// provisioned (free-account builds, before a developer account). Checking
    /// for the container matters: a suite opened without the entitlement can
    /// look fine but not persist.
    static var defaults: UserDefaults {
        if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) != nil,
           let suite = UserDefaults(suiteName: identifier) {
            return suite
        }
        return .standard
    }
}

enum ShieldApplier {

    /// `.grounded` shields the union of the lists that are switched on;
    /// `.unlocked` clears everything. With no list on, nothing is shielded.
    static func apply(_ state: ShieldState, lists: [BlockList], to store: ManagedSettingsStore = ManagedSettingsStore()) {
        switch state {
        case .grounded:
            let selection = BlockLists.combinedSelection(of: lists)
            store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
            // A picked category or website would otherwise silently not block.
            store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
            store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        case .unlocked:
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            store.shield.webDomains = nil
        }
    }

    /// For the extension: re-ground using the lists the app saved.
    static func groundFromSavedLists() {
        apply(.grounded, lists: SharedBlockLists.load() ?? [])
    }
}

extension DeviceActivityName {
    /// One-off window that ends when a Discharge break is due to end.
    static let breakEnd = DeviceActivityName("breakEnd")
    /// Repeating nightly window: force-grounded from the Circuit Breaker time.
    static let circuitBreaker = DeviceActivityName("circuitBreaker")
}
