//
//  VerificationResult.swift
//  Grounded
//
//  The outcome of judging a proof submission — either by Gemini (photo / PDF)
//  or locally (timer).
//

import Foundation

struct VerificationResult: Codable, Equatable {

    /// The single source of truth for what counts as a pass. Confidence is on a
    /// 0–100 scale; anything at or above this passes.
    static let passThreshold: Double = 70

    /// Whether the proof is accepted.
    var passed: Bool
    /// Grader confidence, 0–100.
    var confidence: Double
    /// One actionable sentence for the user.
    var feedback: String
    /// When the judgement was made.
    var verifiedAt: Date

    init(passed: Bool, confidence: Double, feedback: String, verifiedAt: Date = Date()) {
        self.passed = passed
        self.confidence = confidence
        self.feedback = feedback
        self.verifiedAt = verifiedAt
    }

    // MARK: - Reward rules (kept here so views and the view model agree)

    /// Charge awarded for a verified task: +50, plus a +25 bonus at confidence >= 90.
    static func chargeAward(forConfidence confidence: Double) -> Int {
        confidence >= 90 ? 75 : 50
    }

    /// Stars for a verified task: 1 for completion, 2 at confidence >= 80, 3 at >= 90.
    static func stars(forConfidence confidence: Double) -> Int {
        if confidence >= 90 { return 3 }
        if confidence >= 80 { return 2 }
        return 1
    }

    /// Stars this particular result is worth (0 if it did not pass).
    var stars: Int {
        passed ? Self.stars(forConfidence: confidence) : 0
    }
}
