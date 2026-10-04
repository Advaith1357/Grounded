import XCTest

final class NightlyLockoutTests: XCTestCase {

    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    private func date(_ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: hour, minute: minute))!
    }

    func testWindowCrossingMidnight() {
        let lockout = NightlyLockout(startHour: 22, startMinute: 0)
        XCTAssertFalse(lockout.isActive(at: date(21, 59), calendar: calendar))
        XCTAssertTrue(lockout.isActive(at: date(22, 0), calendar: calendar))
        XCTAssertTrue(lockout.isActive(at: date(23, 59), calendar: calendar))
        XCTAssertTrue(lockout.isActive(at: date(0, 0), calendar: calendar))
        XCTAssertTrue(lockout.isActive(at: date(5, 59), calendar: calendar))
        XCTAssertFalse(lockout.isActive(at: date(6, 0), calendar: calendar))
        XCTAssertFalse(lockout.isActive(at: date(12, 0), calendar: calendar))
    }

    func testWindowAfterMidnightDoesNotCrossIt() {
        let lockout = NightlyLockout(startHour: 1, startMinute: 30)
        XCTAssertFalse(lockout.isActive(at: date(1, 29), calendar: calendar))
        XCTAssertTrue(lockout.isActive(at: date(1, 30), calendar: calendar))
        XCTAssertTrue(lockout.isActive(at: date(5, 59), calendar: calendar))
        XCTAssertFalse(lockout.isActive(at: date(6, 0), calendar: calendar))
        XCTAssertFalse(lockout.isActive(at: date(23, 0), calendar: calendar))
    }

    func testStartEqualToEndIsNeverActive() {
        let lockout = NightlyLockout(startHour: 6, startMinute: 0, endHour: 6, endMinute: 0)
        XCTAssertFalse(lockout.isActive(at: date(6, 0), calendar: calendar))
        XCTAssertFalse(lockout.isActive(at: date(12, 0), calendar: calendar))
        XCTAssertEqual(lockout.windowMinutes, 0)
        XCTAssertFalse(lockout.canBeScheduledInBackground)
    }

    func testCustomWakeTime() {
        let lockout = NightlyLockout(startHour: 23, startMinute: 0, endHour: 7, endMinute: 30)
        XCTAssertTrue(lockout.isActive(at: date(7, 29), calendar: calendar))
        XCTAssertFalse(lockout.isActive(at: date(7, 30), calendar: calendar))
        XCTAssertEqual(lockout.windowMinutes, 8 * 60 + 30)
        XCTAssertEqual(lockout.endTimeText(calendar: calendar).replacingOccurrences(of: "\u{202F}", with: " "), "7:30 AM")
    }

    func testWindowUnderFifteenMinutesCannotBeScheduledInBackground() {
        XCTAssertFalse(NightlyLockout(startHour: 5, startMinute: 50, endHour: 6, endMinute: 0).canBeScheduledInBackground)
        XCTAssertTrue(NightlyLockout(startHour: 5, startMinute: 45, endHour: 6, endMinute: 0).canBeScheduledInBackground)
    }

    func testBuildsFromStoredTimeInterval() {
        let start = date(23, 30).timeIntervalSinceReferenceDate
        let wake = date(7, 15).timeIntervalSinceReferenceDate
        let lockout = NightlyLockout(lockoutTimeInterval: start, wakeTimeInterval: wake, calendar: calendar)
        XCTAssertEqual(lockout, NightlyLockout(startHour: 23, startMinute: 30, endHour: 7, endMinute: 15))
    }
}

final class BreakWindowTests: XCTestCase {

    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    private func date(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: hour, minute: minute, second: second))!
    }

    func testLongBreakStartsNow() {
        let window = ShieldSchedule.breakWindow(endingAt: date(15, 30), now: date(15, 0, 12), calendar: calendar)
        XCTAssertEqual(window.start.hour, 15)
        XCTAssertEqual(window.start.minute, 0)
        XCTAssertEqual(window.end.hour, 15)
        XCTAssertEqual(window.end.minute, 30)
    }

    func testShortBreakIsPaddedToTheMinimumInterval() {
        // A 10-minute break: the window must still span 15 minutes, so it
        // starts 5 minutes in the past rather than ending late.
        let window = ShieldSchedule.breakWindow(endingAt: date(15, 10), now: date(15, 0), calendar: calendar)
        XCTAssertEqual(window.end.hour, 15)
        XCTAssertEqual(window.end.minute, 10)
        XCTAssertEqual(window.start.hour, 14)
        XCTAssertEqual(window.start.minute, 55)
    }

    func testEndRoundsUpToTheNextWholeMinute() {
        let window = ShieldSchedule.breakWindow(endingAt: date(15, 30, 1), now: date(15, 0), calendar: calendar)
        XCTAssertEqual(window.end.minute, 31)
    }

    func testWindowCanCrossMidnight() {
        let window = ShieldSchedule.breakWindow(endingAt: date(0, 5).addingTimeInterval(24 * 3600), now: date(23, 50), calendar: calendar)
        XCTAssertEqual(window.start.hour, 23)
        XCTAssertEqual(window.start.minute, 50)
        XCTAssertEqual(window.end.hour, 0)
        XCTAssertEqual(window.end.minute, 5)
    }

    func testWindowIsNeverShorterThanTheMinimum() {
        for minutes in [1, 5, 10, 14, 15, 30] {
            let now = date(12, 0)
            let end = now.addingTimeInterval(TimeInterval(minutes * 60))
            let window = ShieldSchedule.breakWindow(endingAt: end, now: now, calendar: calendar)
            let startMinutes = window.start.hour! * 60 + window.start.minute!
            let endMinutes = window.end.hour! * 60 + window.end.minute!
            let length = ((endMinutes - startMinutes) + 24 * 60) % (24 * 60)
            XCTAssertGreaterThanOrEqual(length, 15, "\(minutes)-minute break")
        }
    }
}
