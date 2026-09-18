//
//  TimerView.swift
//  Grounded
//
//  A focus countdown. Elapsed time is computed from wall-clock `Date`s, not by
//  trusting a repeating `Timer`, so backgrounding the app doesn't stall it.
//  Completing early is allowed; the result reflects the shortfall.
//

import SwiftUI
import UIKit
import Combine

struct TimerView: View {
    let minutes: Int
    /// Called once with the seconds actually spent focused, then the view dismisses.
    let onComplete: (TimeInterval) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Seconds banked from previous running stretches (before the latest pause).
    @State private var banked: TimeInterval = 0
    /// When the current running stretch started; `nil` while paused.
    @State private var runningSince: Date?
    /// Bumped by the ticker to force re-computation.
    @State private var now = Date()
    @State private var didFinish = false

    private let ticker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    private var target: TimeInterval { TimeInterval(max(minutes, 1) * 60) }

    private var elapsed: TimeInterval {
        let live = runningSince.map { now.timeIntervalSince($0) } ?? 0
        return min(banked + max(live, 0), target)
    }

    private var remaining: TimeInterval { max(target - elapsed, 0) }
    private var isRunning: Bool { runningSince != nil }

    var body: some View {
        VStack(spacing: 32) {
            Text(timeString(remaining))
                .font(.system(size: 64, weight: .semibold, design: .monospaced))
                .monospacedDigit()

            Text("\(Int((elapsed / target * 100).rounded()))% of \(minutes) min")
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Button(isRunning ? "Pause" : (elapsed > 0 ? "Resume" : "Start")) {
                    toggleRunning()
                }
                .buttonStyle(.bordered)

                Button("Complete") {
                    finish()
                }
                .buttonStyle(.borderedProminent)
            }

            Text("Completing before the timer ends still submits — it just scores lower.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            if runningSince == nil && banked == 0 {
                runningSince = Date() // auto-start
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onReceive(ticker) { tick in
            now = tick
            if isRunning && elapsed >= target {
                finish()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            now = Date()
        }
    }

    private func toggleRunning() {
        if let start = runningSince {
            banked += max(now.timeIntervalSince(start), 0)
            runningSince = nil
        } else {
            runningSince = Date()
        }
        now = Date()
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true

        var total = banked
        if let start = runningSince {
            total += max(Date().timeIntervalSince(start), 0)
        }
        onComplete(min(total, target))
        dismiss()
    }

    private func timeString(_ interval: TimeInterval) -> String {
        let whole = Int(interval.rounded(.up))
        return String(format: "%02d:%02d", whole / 60, whole % 60)
    }
}

#if DEBUG
#Preview {
    TimerView(minutes: 1) { seconds in
        print("focused for \(seconds)s")
    }
}
#endif
