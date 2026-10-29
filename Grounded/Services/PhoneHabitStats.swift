//
//  PhoneHabitStats.swift
//  Grounded
//
//  The "how much of your life is this" numbers shown in onboarding. They're a
//  rough illustration built on two stated assumptions (shown to the user): 16
//  waking hours a day, and living to 80. Foundation only, so it's testable.
//

import Foundation

struct PhoneHabitStats: Equatable {
    static let wakingHoursPerDay = 16.0
    static let assumedLifeExpectancy = 80

    let hoursPerDay: Double
    let age: Int

    /// Share of your waking hours spent on the phone, 0...100.
    var percentOfWakingLife: Double {
        Self.percentOfWakingLife(hoursPerDay: hoursPerDay)
    }

    /// Full 24-hour days per year spent on the phone.
    var daysPerYear: Double { hoursPerDay * 365 / 24 }

    var remainingYears: Int { max(0, Self.assumedLifeExpectancy - age) }

    /// Years of your remaining life (counted in 24-hour days) spent on the phone.
    var yearsOfRemainingLife: Double { hoursPerDay / 24 * Double(remainingYears) }

    /// Years of remaining life handed back by capping at `goalMinutes` a day;
    /// 0 when the goal isn't below your current use.
    func yearsSaved(goalMinutes: Int) -> Double {
        let goalHours = Double(goalMinutes) / 60
        guard goalHours < hoursPerDay else { return 0 }
        return (hoursPerDay - goalHours) / 24 * Double(remainingYears)
    }

    static func percentOfWakingLife(hoursPerDay: Double) -> Double {
        min(1, max(0, hoursPerDay / wakingHoursPerDay)) * 100
    }

    // MARK: - Formatting

    /// "12.5 years", "8 months", or "under a month".
    static func durationText(years: Double) -> String {
        if years >= 1 { return String(format: "%.1f years", years) }
        let months = years * 12
        if months >= 1 { return String(format: "%.0f months", months) }
        return "under a month"
    }

    /// "5.5 h" / "5 h"
    static func hoursText(_ hours: Double) -> String {
        hours.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f h", hours)
            : String(format: "%.1f h", hours)
    }
}
