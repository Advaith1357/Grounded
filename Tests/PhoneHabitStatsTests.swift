import XCTest

final class PhoneHabitStatsTests: XCTestCase {

    func testPercentOfWakingLife() {
        XCTAssertEqual(PhoneHabitStats(hoursPerDay: 4, age: 20).percentOfWakingLife, 25, accuracy: 0.001)
        XCTAssertEqual(PhoneHabitStats(hoursPerDay: 8, age: 20).percentOfWakingLife, 50, accuracy: 0.001)
    }

    func testPercentIsCappedAtAllWakingHours() {
        XCTAssertEqual(PhoneHabitStats(hoursPerDay: 20, age: 20).percentOfWakingLife, 100, accuracy: 0.001)
        XCTAssertEqual(PhoneHabitStats(hoursPerDay: 0, age: 20).percentOfWakingLife, 0, accuracy: 0.001)
    }

    func testDaysPerYear() {
        // 6 h a day = a quarter of every day = 91.25 full days a year.
        XCTAssertEqual(PhoneHabitStats(hoursPerDay: 6, age: 20).daysPerYear, 91.25, accuracy: 0.001)
    }

    func testRemainingLifeUsesTheAssumedLifeExpectancy() {
        let stats = PhoneHabitStats(hoursPerDay: 6, age: 20)
        XCTAssertEqual(stats.remainingYears, 60)
        // A quarter of 60 years.
        XCTAssertEqual(stats.yearsOfRemainingLife, 15, accuracy: 0.001)
    }

    func testNoRemainingYearsPastTheAssumedLifeExpectancy() {
        let stats = PhoneHabitStats(hoursPerDay: 6, age: 95)
        XCTAssertEqual(stats.remainingYears, 0)
        XCTAssertEqual(stats.yearsOfRemainingLife, 0, accuracy: 0.001)
    }

    func testYearsSavedByALowerGoal() {
        // 6 h -> 2 h on 60 remaining years: (4/24) * 60 = 10 years.
        XCTAssertEqual(PhoneHabitStats(hoursPerDay: 6, age: 20).yearsSaved(goalMinutes: 120), 10, accuracy: 0.001)
    }

    func testNothingSavedWhenTheGoalIsNotBelowCurrentUse() {
        let stats = PhoneHabitStats(hoursPerDay: 2, age: 20)
        XCTAssertEqual(stats.yearsSaved(goalMinutes: 120), 0)
        XCTAssertEqual(stats.yearsSaved(goalMinutes: 300), 0)
    }

    func testDurationText() {
        XCTAssertEqual(PhoneHabitStats.durationText(years: 12.46), "12.5 years")
        XCTAssertEqual(PhoneHabitStats.durationText(years: 0.5), "6 months")
        XCTAssertEqual(PhoneHabitStats.durationText(years: 0.01), "under a month")
    }

    func testHoursText() {
        XCTAssertEqual(PhoneHabitStats.hoursText(5), "5 h")
        XCTAssertEqual(PhoneHabitStats.hoursText(5.5), "5.5 h")
    }
}
