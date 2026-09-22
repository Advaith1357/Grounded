//
//  InsightsView.swift
//  Grounded
//
//  Insights tab — analytics. The Trickle Buffer card that used to live here
//  moved to Queue's sticky banner (it's about "what's happening right now
//  while I'm working", not a historical/analytical view). The Weekly Voltage
//  chart and Recent Voltage Feeds list moved IN from the old Grid tab, since
//  Grid is now the social friends list. A GitHub-style contribution heatmap
//  sits at the top, built from real completion dates.
//

import SwiftUI

struct InsightsView: View {
    @ObservedObject var viewModel: GroundedViewModel

    private var completionDates: [Date] {
        viewModel.history
            .filter { $0.task.status == .completed }
            .compactMap { $0.task.completedAt }
    }

    private var completionRate: Double? {
        let completed = viewModel.history.filter { $0.task.status == .completed }.count
        let abandoned = viewModel.history.filter { $0.task.status == .abandoned }.count
        let total = completed + abandoned
        guard total > 0 else { return nil }
        return Double(completed) / Double(total)
    }

    private var recentFeed: [GroundedViewModel.HistoryEntry] {
        Array(viewModel.history.filter { $0.task.status == .completed }.prefix(5))
    }

    private var weeklyVoltage: [(dayLabel: String, total: Int, isToday: Bool)] {
        let calendar = Calendar.current
        return (0..<7).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
            let count = completionDates.filter { calendar.isDate($0, inSameDayAs: day) }.count
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEEE"
            return (formatter.string(from: day), count * VerificationResult.flatReward, calendar.isDateInToday(day))
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NexusColor.background.ignoresSafeArea()
                CircuitBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        heatmapCard
                        balanceCard
                        chartCard
                        activityLog
                        streakAndRateRow
                    }
                    .padding(NexusMetrics.screenPadding)
                }
            }
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Heatmap

    private var heatmapCard: some View {
        NexusCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Activity Heatmap")
                    .font(NexusFont.sans(14, weight: .bold))
                    .foregroundStyle(NexusColor.textPrimary)
                ContributionHeatmap(completionDates: completionDates)
                Text("Darker = more tasks verified that day.")
                    .font(NexusFont.sans(11))
                    .foregroundStyle(NexusColor.textSecondary)
            }
        }
    }

    // MARK: - Balance

    private var balanceCard: some View {
        NexusCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("VOLTAGE BALANCE")
                    .font(NexusFont.mono(12))
                    .foregroundStyle(NexusColor.textSecondary)
                Text("\(viewModel.economy.voltageBalance) V")
                    .font(NexusFont.mono(36, weight: .heavy))
                    .foregroundStyle(NexusColor.accent)
                Text("\(viewModel.economy.voltageBalance) minutes of screen time banked")
                    .font(NexusFont.sans(12))
                    .foregroundStyle(NexusColor.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Weekly chart (moved from the old Grid tab)

    private var chartCard: some View {
        NexusCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("Weekly Voltage Earned")
                    .font(NexusFont.sans(14, weight: .bold))
                    .foregroundStyle(NexusColor.textPrimary)

                let maxTotal = max(weeklyVoltage.map(\.total).max() ?? 0, 1)
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(Array(weeklyVoltage.enumerated()), id: \.offset) { _, point in
                        VStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(point.total > 0 ? NexusColor.accent : NexusColor.surfaceElevated)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(point.total > 0 ? NexusColor.accent : NexusColor.border)
                                )
                                .frame(height: 12 + CGFloat(point.total) / CGFloat(maxTotal) * 88)
                            Text(point.dayLabel)
                                .font(NexusFont.mono(12))
                                .foregroundStyle(point.isToday ? NexusColor.accent : NexusColor.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 120, alignment: .bottom)
            }
        }
    }

    // MARK: - Recent activity (moved from the old Grid tab)

    private var activityLog: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Voltage Feeds")
                .font(NexusFont.sans(16, weight: .bold))
                .foregroundStyle(NexusColor.textPrimary)

            if recentFeed.isEmpty {
                Text("No verified tasks yet.")
                    .font(NexusFont.sans(13))
                    .foregroundStyle(NexusColor.textSecondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(recentFeed) { entry in
                        activityRow(for: entry)
                    }
                }
            }
        }
    }

    private func activityRow(for entry: GroundedViewModel.HistoryEntry) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(NexusColor.surfaceElevated)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(NexusColor.accent)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.task.title)
                    .font(NexusFont.sans(14, weight: .bold))
                    .foregroundStyle(NexusColor.textPrimary)
                    .lineLimit(1)
                Text(Self.relativeLabel(for: entry.task.completedAt ?? entry.task.createdAt))
                    .font(NexusFont.sans(11))
                    .foregroundStyle(NexusColor.textSecondary)
            }
            Spacer()
            Text("+\(VerificationResult.flatReward) V")
                .font(NexusFont.mono(14))
                .foregroundStyle(NexusColor.accent)
        }
        .padding(14)
        .background(NexusColor.surface)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(NexusColor.border))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Streak / completion rate

    private var streakAndRateRow: some View {
        HStack(spacing: 12) {
            NexusStatTile(label: "LONGEST STREAK", value: "\(viewModel.economy.longestStreak) Days")
            if let completionRate {
                NexusStatTile(
                    label: "COMPLETION RATE",
                    value: "\(Int((completionRate * 100).rounded()))%",
                    valueColor: NexusColor.accent
                )
            } else {
                NexusStatTile(label: "COMPLETION RATE", value: "—")
            }
        }
    }

    private static func relativeLabel(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return "Today, \(formatter.string(from: date))"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }
}

/// A GitHub-style contribution grid: columns are weeks (oldest to newest,
/// left to right), rows are the 7 days of the week. Built from real
/// `completedAt` dates, not placeholder/random data.
private struct ContributionHeatmap: View {
    let completionDates: [Date]
    var weeks = 10

    private var grid: [[Int]] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let totalDays = weeks * 7
        let counts: [Int] = (0..<totalDays).reversed().map { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return 0 }
            return completionDates.filter { calendar.isDate($0, inSameDayAs: day) }.count
        }
        return stride(from: 0, to: counts.count, by: 7).map { start in
            Array(counts[start..<min(start + 7, counts.count)])
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(grid.enumerated()), id: \.offset) { _, week in
                VStack(spacing: 3) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, count in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color(forCount: count))
                            .frame(width: 12, height: 12)
                    }
                }
            }
        }
    }

    private func color(forCount count: Int) -> Color {
        guard count > 0 else { return NexusColor.surfaceElevated }
        let intensity = min(1.0, 0.35 + Double(count) * 0.3)
        return NexusColor.accent.opacity(intensity)
    }
}

#if DEBUG
#Preview {
    InsightsView(viewModel: .previewIdle())
}
#endif
