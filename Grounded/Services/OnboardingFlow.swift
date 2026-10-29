//
//  OnboardingFlow.swift
//  Grounded
//
//  The shape of the first-run questionnaire: its steps in order, and the
//  daily-limit choices. Foundation only, so it's testable.
//

import Foundation

enum OnboardingStep: Int, CaseIterable {
    case account
    case habits
    case numbers
    case goal
    case blockList
    case friends
    case finish

    var next: OnboardingStep? { Self(rawValue: rawValue + 1) }
    var previous: OnboardingStep? { Self(rawValue: rawValue - 1) }

    /// 1-based position, for "STEP 3 OF 7".
    var number: Int { rawValue + 1 }
    static var count: Int { allCases.count }

    var progress: Double { Double(number) / Double(Self.count) }
}

/// The maximum screen time the user allows themselves per day, in minutes.
/// 1V = 1 minute, so this is also the ceiling on the Queue's "daily load".
enum DailyLimit {
    static let range = 15...720
    static let step = 15
    static let defaultMinutes = 120
    static let presets = [30, 60, 90, 120, 180]

    static func clamped(_ minutes: Int) -> Int {
        min(max(minutes, range.lowerBound), range.upperBound)
    }

    /// "2 h", "1 h 30 min", "45 min"
    static func label(minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return "\(rest) min"
        case (_, 0): return "\(hours) h"
        default: return "\(hours) h \(rest) min"
        }
    }
}
