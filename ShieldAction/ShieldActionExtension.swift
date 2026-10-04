//
//  ShieldActionExtension.swift
//  ShieldAction
//
//  Handles taps on the interceptor screen's buttons. A shield action can't
//  open the host app, so the primary button posts a local notification
//  ("tap to open Grounded") and closes the blocked app; tapping the
//  notification launches Grounded, where the user can Discharge.
//

import ManagedSettings
import UserNotifications

final class ShieldActionExtension: ShieldActionDelegate {

    override func handle(action: ShieldAction, for application: ApplicationToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        respond(to: action, completionHandler: completionHandler)
    }

    override func handle(action: ShieldAction, for webDomain: WebDomainToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        respond(to: action, completionHandler: completionHandler)
    }

    override func handle(action: ShieldAction, for category: ActivityCategoryToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        respond(to: action, completionHandler: completionHandler)
    }

    private func respond(to action: ShieldAction, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        guard action == .primaryButtonPressed else {
            completionHandler(.close)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "[ GROUNDED ]"
        content.body = "Open Grounded and tap Discharge to spend Voltage."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "shield.discharge-reminder", content: content, trigger: nil)

        UNUserNotificationCenter.current().add(request) { _ in
            completionHandler(.close)
        }
    }
}
