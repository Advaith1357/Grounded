//
//  TrickleSchedule.swift
//  Grounded
//
//  The passive-charge rules in one place: while the queue is empty, +1V every
//  `interval`, never pushing the balance past `cap`. Foundation only, so the
//  timing is unit-testable and the Queue's countdown can share it with the
//  view model.
//

import Foundation

enum TrickleSchedule {
    static let interval: TimeInterval = 5 * 60
    static let cap = 20

    /// Whole intervals elapsed since `lastTrickleAt`.
    static func ticksDue(lastTrickleAt: Date, now: Date) -> Int {
        Int(max(0, now.timeIntervalSince(lastTrickleAt)) / interval)
    }

    /// Seconds until the next +1V (always within 0...interval).
    static func secondsUntilNext(lastTrickleAt: Date, now: Date) -> TimeInterval {
        let elapsed = max(0, now.timeIntervalSince(lastTrickleAt))
        return interval - elapsed.truncatingRemainder(dividingBy: interval)
    }

    /// What the charge is doing, for the Queue's banner.
    enum Status: Equatable {
        case pausedWhileTaskQueued
        case full
        case charging(secondsUntilNext: TimeInterval)
    }

    static func status(queueIsEmpty: Bool, balance: Int, lastTrickleAt: Date, now: Date) -> Status {
        guard queueIsEmpty else { return .pausedWhileTaskQueued }
        guard balance < cap else { return .full }
        return .charging(secondsUntilNext: secondsUntilNext(lastTrickleAt: lastTrickleAt, now: now))
    }

    /// "4:12"
    static func countdownText(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds.rounded(.up)))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}
