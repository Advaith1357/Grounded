//
//  GroundingNotifier.swift
//  Grounded
//
//  A local notification a minute before a Discharge break ends. It's handed to
//  the OS up front, so it fires even if Grounded is closed. It's a plain local
//  notification: no developer account, entitlement, or server involved.
//

import Foundation
import UserNotifications

protocol GroundingNotifier: AnyObject {
    func scheduleBreakWarning(endsAt: Date)
    func cancelBreakWarning()
}

final class LocalGroundingNotifier: GroundingNotifier {

    static let shared = LocalGroundingNotifier()
    private let center = UNUserNotificationCenter.current()

    func scheduleBreakWarning(endsAt: Date) {
        cancelBreakWarning()
        guard let planned = BreakWarningPlan.warning(endsAt: endsAt) else { return }

        let content = UNMutableNotificationContent()
        content.title = planned.title
        content.body = planned.body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: planned.fireIn, repeats: false)
        center.add(UNNotificationRequest(identifier: planned.identifier, content: content, trigger: trigger)) { error in
            if let error { print("[GroundingNotifier] couldn't schedule the break warning: \(error)") }
        }
    }

    func cancelBreakWarning() {
        center.removePendingNotificationRequests(withIdentifiers: [BreakWarningPlan.warningIdentifier])
    }
}

/// Preview/test stand-in.
final class NoopGroundingNotifier: GroundingNotifier {
    func scheduleBreakWarning(endsAt: Date) {}
    func cancelBreakWarning() {}
}

/// By default iOS drops notifications that arrive while the app is on screen.
/// The one-minute warning should still show.
final class ForegroundNotificationPresenter: NSObject, UNUserNotificationCenterDelegate {

    static let shared = ForegroundNotificationPresenter()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
