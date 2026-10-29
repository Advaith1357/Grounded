import XCTest

final class TrickleScheduleTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_000_000)

    func testNoTickBeforeAFullInterval() {
        XCTAssertEqual(TrickleSchedule.ticksDue(lastTrickleAt: start, now: start.addingTimeInterval(299)), 0)
        XCTAssertEqual(TrickleSchedule.ticksDue(lastTrickleAt: start, now: start.addingTimeInterval(300)), 1)
    }

    func testSeveralMissedTicksAreCountedAfterTimeAway() {
        XCTAssertEqual(TrickleSchedule.ticksDue(lastTrickleAt: start, now: start.addingTimeInterval(300 * 4 + 120)), 4)
    }

    func testAClockThatWentBackwardsNeverProducesTicks() {
        XCTAssertEqual(TrickleSchedule.ticksDue(lastTrickleAt: start, now: start.addingTimeInterval(-500)), 0)
    }

    func testCountdownRunsFromAFullIntervalDownToZero() {
        XCTAssertEqual(TrickleSchedule.secondsUntilNext(lastTrickleAt: start, now: start), 300)
        XCTAssertEqual(TrickleSchedule.secondsUntilNext(lastTrickleAt: start, now: start.addingTimeInterval(60)), 240)
        XCTAssertEqual(TrickleSchedule.secondsUntilNext(lastTrickleAt: start, now: start.addingTimeInterval(299)), 1)
    }

    func testCountdownWrapsWhenTicksAreOverdue() {
        // 7 minutes in with no tick applied yet: 2 minutes into the *next* interval... 
        XCTAssertEqual(TrickleSchedule.secondsUntilNext(lastTrickleAt: start, now: start.addingTimeInterval(420)), 180)
    }

    func testCountdownText() {
        XCTAssertEqual(TrickleSchedule.countdownText(252), "4:12")
        XCTAssertEqual(TrickleSchedule.countdownText(300), "5:00")
        XCTAssertEqual(TrickleSchedule.countdownText(0.2), "0:01")
        XCTAssertEqual(TrickleSchedule.countdownText(-5), "0:00")
    }

    func testStatusPausedWhileATaskIsQueued() {
        XCTAssertEqual(TrickleSchedule.status(queueIsEmpty: false, balance: 3, lastTrickleAt: start, now: start), .pausedWhileTaskQueued)
        // Even at the cap, a queued task is the more useful thing to say.
        XCTAssertEqual(TrickleSchedule.status(queueIsEmpty: false, balance: 20, lastTrickleAt: start, now: start), .pausedWhileTaskQueued)
    }

    func testStatusFullAtOrAboveTheCap() {
        XCTAssertEqual(TrickleSchedule.status(queueIsEmpty: true, balance: 20, lastTrickleAt: start, now: start), .full)
        XCTAssertEqual(TrickleSchedule.status(queueIsEmpty: true, balance: 34, lastTrickleAt: start, now: start), .full)
    }

    func testStatusChargingShowsTheCountdown() {
        XCTAssertEqual(
            TrickleSchedule.status(queueIsEmpty: true, balance: 10, lastTrickleAt: start, now: start.addingTimeInterval(48)),
            .charging(secondsUntilNext: 252)
        )
    }
}
