//
//  VerificationResult.swift
//  Grounded
//
//  The outcome of Gemini judging a proof submission.
//
//  Reward is now a strict flat rate, not confidence-scaled: every passing
//  submission is worth exactly `flatReward` Voltage, full stop. Confidence
//  still decides pass/fail via `passThreshold` — it just no longer decides
//  the payout amount.
//

import Foundation

struct VerificationResult: Codable, Equatable {

    /// Confidence (0-100) at or above this passes.
    static let passThreshold: Double = 70

    /// Flat Voltage payout for any passing submission. 1V = 1 minute of screen time.
    static let flatReward: Int = 10

    var passed: Bool
    var confidence: Double
    var feedback: String
    var verifiedAt: Date

    init(passed: Bool, confidence: Double, feedback: String, verifiedAt: Date = Date()) {
        self.passed = passed
        self.confidence = confidence
        self.feedback = feedback
        self.verifiedAt = verifiedAt
    }
}
