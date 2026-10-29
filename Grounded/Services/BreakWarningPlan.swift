//
//  BreakWarningPlan.swift
//  Grounded
//
//  When to warn that a Discharge break is about to end. Pure Foundation so
//  the timing is unit-testable; GroundingNotifier turns it into a real local
//  notification.
//

import Foundation

struct PlannedNotification: Equatable {
    let identifier: String
    let title: String
    let body: String
    /// Seconds from "now" until it should fire.
    let fireIn: TimeInterval
}

enum BreakWarningPlan {

    static let warningIdentifier = "break.warning"
    /// How long before the break ends the heads-up fires.
    static let warningLead: TimeInterval = 60
    /// A warning that would fire sooner than this after scheduling isn't worth sending.
    private static let minimumDelay: TimeInterval = 5

    /// The "1 minute left" heads-up, or nil when the break is already too
    /// close to its end for one to make sense.
    static func warning(endsAt: Date, now: Date = Date()) -> PlannedNotification? {
        let delay = endsAt.timeIntervalSince(now) - warningLead
        guard delay > minimumDelay else { return nil }
        return PlannedNotification(
            identifier: warningIdentifier,
            title: "[ 1 MINUTE LEFT ]",
            body: "Your break is almost over. Wrap up and get off your apps.",
            fireIn: delay
        )
    }
}
