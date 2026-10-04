//
//  ShieldShared.swift
//  Shared by the app and the DeviceActivityMonitor extension.
//
//  The extension can't see the app's memory or sandbox, so everything it needs
//  to re-apply the shield travels through the App Group: the picked apps
//  (FamilyActivitySelection, encoded in the group's UserDefaults) and the
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
    static let identifier = "group.com.grounded.app"

    /// Falls back to standard defaults if the group isn't provisioned yet
    /// (simulator builds, or before the developer account is set up).
    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}

enum SharedSelection {
    private static let key = "settings.familyActivitySelection"

    static func load() -> FamilyActivitySelection {
        guard
            let data = AppGroup.defaults.data(forKey: key),
            let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return FamilyActivitySelection() }
        return selection
    }

    static func save(_ selection: FamilyActivitySelection) {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        AppGroup.defaults.set(data, forKey: key)
    }
}

enum ShieldApplier {

    static func apply(_ state: ShieldState, selection: FamilyActivitySelection, to store: ManagedSettingsStore = ManagedSettingsStore()) {
        switch state {
        case .grounded:
            store.shield.applications = selection.applicationTokens
            // A picked category or website would otherwise silently not block.
            store.shield.applicationCategories = .specific(selection.categoryTokens)
            store.shield.webDomains = selection.webDomainTokens
        case .unlocked:
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            store.shield.webDomains = nil
        }
    }

    /// For the extension: re-ground using the selection saved by the app.
    static func groundFromSavedSelection() {
        apply(.grounded, selection: SharedSelection.load())
    }
}

extension DeviceActivityName {
    /// One-off window that ends when a Discharge break is due to end.
    static let breakEnd = DeviceActivityName("breakEnd")
    /// Repeating nightly window: force-grounded from the Circuit Breaker time.
    static let circuitBreaker = DeviceActivityName("circuitBreaker")
}
