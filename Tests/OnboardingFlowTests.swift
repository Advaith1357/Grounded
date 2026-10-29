import XCTest

final class OnboardingFlowTests: XCTestCase {

    func testStepsRunInOrderFromAccountToFinish() {
        XCTAssertEqual(OnboardingStep.allCases, [.account, .habits, .numbers, .goal, .blockList, .friends, .finish])
    }

    func testNavigationStopsAtBothEnds() {
        XCTAssertNil(OnboardingStep.account.previous)
        XCTAssertEqual(OnboardingStep.account.next, .habits)
        XCTAssertEqual(OnboardingStep.friends.next, .finish)
        XCTAssertNil(OnboardingStep.finish.next)
    }

    func testProgressEndsAtOne() {
        XCTAssertEqual(OnboardingStep.account.number, 1)
        XCTAssertEqual(OnboardingStep.finish.number, OnboardingStep.count)
        XCTAssertEqual(OnboardingStep.finish.progress, 1, accuracy: 0.0001)
    }

    func testDailyLimitLabels() {
        XCTAssertEqual(DailyLimit.label(minutes: 45), "45 min")
        XCTAssertEqual(DailyLimit.label(minutes: 120), "2 h")
        XCTAssertEqual(DailyLimit.label(minutes: 90), "1 h 30 min")
    }

    func testDailyLimitIsClampedToItsRange() {
        XCTAssertEqual(DailyLimit.clamped(0), 15)
        XCTAssertEqual(DailyLimit.clamped(5000), 720)
        XCTAssertEqual(DailyLimit.clamped(100), 100)
    }

    func testDefaultAndPresetsAreInsideTheRange() {
        XCTAssertTrue(DailyLimit.range.contains(DailyLimit.defaultMinutes))
        XCTAssertTrue(DailyLimit.presets.allSatisfy { DailyLimit.range.contains($0) })
    }
}
