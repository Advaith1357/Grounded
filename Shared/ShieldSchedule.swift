//
//  ShieldSchedule.swift
//  Pure date math for DeviceActivity schedules (Foundation only, so it's
//  unit-testable without the Screen Time frameworks).
//

import Foundation

enum ShieldSchedule {

    /// DeviceActivity rejects schedules shorter than this.
    static let minimumInterval: TimeInterval = 15 * 60

    /// The one-off window used to re-ground when a break ends while the app
    /// isn't running. It ends at the break's end rounded UP to the next whole
    /// minute (schedules are minute-resolution). Breaks shorter than 15
    /// minutes — the 10V option — are padded by starting the window earlier,
    /// since moving the end later would leave the apps open too long.
    static func breakWindow(
        endingAt end: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (start: DateComponents, end: DateComponents) {
        let roundedEnd = ceilToMinute(end)
        let flooredNow = floorToMinute(now)
        let start = min(flooredNow, roundedEnd.addingTimeInterval(-minimumInterval))
        return (
            calendar.dateComponents([.hour, .minute], from: start),
            calendar.dateComponents([.hour, .minute], from: roundedEnd)
        )
    }

    static func ceilToMinute(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded(.up) * 60)
    }

    static func floorToMinute(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
    }
}
