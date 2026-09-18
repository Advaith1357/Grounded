//
//  ProofResultView.swift
//  Grounded
//
//  Verdict screen: pass/fail, confidence, feedback, stars, Continue.
//

import SwiftUI

struct ProofResultView: View {
    let result: VerificationResult
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: result.passed ? "checkmark.seal.fill" : "xmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(result.passed ? .green : .red)

            Text(result.passed ? "Proof verified" : "Not verified")
                .font(.title2.bold())

            if result.passed {
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { index in
                        Image(systemName: index < result.stars ? "star.fill" : "star")
                            .foregroundStyle(.yellow)
                    }
                }
                .font(.title3)
                .accessibilityLabel("\(result.stars) out of 3 stars")
            }

            VStack(spacing: 8) {
                Text("Confidence: \(Int(result.confidence.rounded()))%")
                    .font(.headline)
                Text(result.feedback)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            if result.passed {
                Text("Current restored — your apps are unblocked.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Your task is still active. Fix the proof and try again.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button("Continue", action: onContinue)
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
#Preview("Pass") {
    ProofResultView(
        result: VerificationResult(passed: true, confidence: 93,
                                   feedback: "All ten matrix problems are worked through by hand with final answers boxed."),
        onContinue: {}
    )
}

#Preview("Fail") {
    ProofResultView(
        result: VerificationResult(passed: false, confidence: 22,
                                   feedback: "The photo shows a blank sheet of paper — no worked problems are visible."),
        onContinue: {}
    )
}
#endif
