//
//  BlockLists.swift
//  Shared by the app and the DeviceActivityMonitor extension.
//
//  A block list is a named set of apps / categories / websites with its own
//  on/off switch. Only lists that are switched ON (and contain something) are
//  shielded, and a shielded app is only intercepted when you open it. Switch a
//  list off to stop blocking its apps without losing the list.
//

import Foundation
import FamilyControls

struct BlockList: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var selection = FamilyActivitySelection()
    var isEnabled = true

    /// Apps + categories + websites in the list.
    var itemCount: Int {
        selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
    }

    /// Switched on and actually containing something to block.
    var isBlocking: Bool { isEnabled && itemCount > 0 }

    /// The subtitle shown under the list's name. `blockingAvailable` is false
    /// in a build without Screen Time, where nothing is ever blocked.
    func statusText(blockingAvailable: Bool) -> String {
        guard blockingAvailable else {
            return itemCount == 0 ? "PAUSED · NO APPS YET" : "PAUSED · \(itemCount) SELECTED"
        }
        switch (isEnabled, itemCount) {
        case (true, 0): return "ON · PICK APPS TO START BLOCKING"
        case (true, let n): return "BLOCKING · \(n) SELECTED"
        case (false, 0): return "NO APPS YET"
        case (false, let n): return "OFF · \(n) SELECTED"
        }
    }
}

enum BlockLists {

    /// Everything that should be shielded right now: the union of the
    /// switched-on lists.
    static func combinedSelection(of lists: [BlockList]) -> FamilyActivitySelection {
        var combined = FamilyActivitySelection()
        for list in lists where list.isBlocking {
            combined.applicationTokens.formUnion(list.selection.applicationTokens)
            combined.categoryTokens.formUnion(list.selection.categoryTokens)
            combined.webDomainTokens.formUnion(list.selection.webDomainTokens)
        }
        return combined
    }

    /// Names of the lists currently blocking, in display order.
    static func blockingNames(of lists: [BlockList]) -> [String] {
        lists.filter(\.isBlocking).map(\.name)
    }
}

/// Persistence in the App Group, so the extension sees what the app saved.
enum SharedBlockLists {
    static let key = "blocklists.v1"

    /// `nil` when nothing has ever been saved (first launch).
    static func load(from defaults: UserDefaults = AppGroup.defaults) -> [BlockList]? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode([BlockList].self, from: data)
    }

    static func save(_ lists: [BlockList], to defaults: UserDefaults = AppGroup.defaults) {
        guard let data = try? JSONEncoder().encode(lists) else { return }
        defaults.set(data, forKey: key)
    }
}
