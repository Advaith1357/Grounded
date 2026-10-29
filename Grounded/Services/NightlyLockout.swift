//
//  NightlyLockout.swift
//  Grounded
//
//  The "Circuit Breaker": from the user's chosen lockout time until their
//  chosen wake time, the shield is forced on and Discharge is unavailable.
//  Foundation only, so the window math is unit-testable.
//

import Foundation

struct NightlyLockout: Equatable {
    static let defaultStart = (hour: 22, minute: 0)
    static let defaultWake = (hour: 6, minute: 0)

    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int

    init(
        startHour: Int,
        startMinute: Int,
        endHour: Int = NightlyLockout.defaultWake.hour,
        endMinute: Int = NightlyLockout.defaultWake.minute
    ) {
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
    }

    /// From the stored settings (each a `timeIntervalSinceReferenceDate` whose
    /// time-of-day is the only part that matters).
    init(lockoutTimeInterval: Double, wakeTimeInterval: Double, calendar: Calendar = .current) {
        func time(_ interval: Double) -> (hour: Int, minute: Int) {
            let c = calendar.dateComponents([.hour, .minute], from: Date(timeIntervalSinceReferenceDate: interval))
            return (c.hour ?? 0, c.minute ?? 0)
        }
        let start = time(lockoutTimeInterval)
        let end = time(wakeTimeInterval)
        self.init(startHour: start.hour, startMinute: start.minute, endHour: end.hour, endMinute: end.minute)
    }

    var startComponents: DateComponents { DateComponents(hour: startHour, minute: startMinute) }
    var endComponents: DateComponents { DateComponents(hour: endHour, minute: endMinute) }

    private var startMinutes: Int { startHour * 60 + startMinute }
    private var endMinutes: Int { endHour * 60 + endMinute }

    /// Length of the window in minutes, wrapping past midnight. 0 when the
    /// start and end are the same time (no lockout).
    var windowMinutes: Int {
        ((endMinutes - startMinutes) + 24 * 60) % (24 * 60)
    }

    /// DeviceActivity rejects schedules shorter than 15 minutes, so a shorter
    /// window is still enforced in-app but can't be enforced in the background.
    var canBeScheduledInBackground: Bool {
        windowMinutes >= Int(ShieldSchedule.minimumInterval / 60)
    }

    /// Whether the lockout window contains `date`. The window can cross
    /// midnight (the usual case: 10 PM -> 6 AM).
    func isActive(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let now = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        if startMinutes == endMinutes { return false }
        return startMinutes < endMinutes
            ? (now >= startMinutes && now < endMinutes)
            : (now >= startMinutes || now < endMinutes)
    }

    /// The wake time as UI copy, e.g. "6:00 AM".
    func endTimeText(calendar: Calendar = .current) -> String {
        let date = calendar.date(from: endComponents) ?? Date()
        // Format in the calendar's own zone, not whatever the device is in, so
        // the text always matches the components it was built from.
        return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: .current, calendar: calendar, timeZone: calendar.timeZone))
    }
}
