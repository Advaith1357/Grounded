import XCTest

final class BreakWarningPlanTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testTenMinuteBreakWarnsAtNineMinutes() {
        let warning = BreakWarningPlan.warning(endsAt: now.addingTimeInterval(600), now: now)
        XCTAssertEqual(warning?.identifier, BreakWarningPlan.warningIdentifier)
        XCTAssertEqual(warning?.fireIn, 540)
    }

    func testThirtyMinuteBreakWarnsOneMinuteBeforeTheEnd() {
        let warning = BreakWarningPlan.warning(endsAt: now.addingTimeInterval(1800), now: now)
        XCTAssertEqual(warning?.fireIn, 1800 - BreakWarningPlan.warningLead)
    }

    func testNoWarningWhenLessThanAMinuteIsLeft() {
        XCTAssertNil(BreakWarningPlan.warning(endsAt: now.addingTimeInterval(45), now: now))
        XCTAssertNil(BreakWarningPlan.warning(endsAt: now.addingTimeInterval(BreakWarningPlan.warningLead), now: now))
    }

    func testNoWarningRightAtTheBoundary() {
        // A warning due in 3 seconds isn't worth sending.
        XCTAssertNil(BreakWarningPlan.warning(endsAt: now.addingTimeInterval(BreakWarningPlan.warningLead + 3), now: now))
        XCTAssertNotNil(BreakWarningPlan.warning(endsAt: now.addingTimeInterval(BreakWarningPlan.warningLead + 6), now: now))
    }

    func testNoWarningForABreakThatIsOver() {
        XCTAssertNil(BreakWarningPlan.warning(endsAt: now.addingTimeInterval(-10), now: now))
        XCTAssertNil(BreakWarningPlan.warning(endsAt: now, now: now))
    }

    func testTheCopyTellsYouToGetOffYourApps() {
        let warning = BreakWarningPlan.warning(endsAt: now.addingTimeInterval(600), now: now)
        XCTAssertEqual(warning?.title, "[ 1 MINUTE LEFT ]")
        XCTAssertTrue(warning?.body.lowercased().contains("get off your apps") == true)
    }
}
