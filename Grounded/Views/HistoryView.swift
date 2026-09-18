//
//  HistoryView.swift
//  Grounded
//
//  Past tasks with their verdict and stars.
//

import SwiftUI

struct HistoryView: View {
    let entries: [GroundedViewModel.HistoryEntry]

    var body: some View {
        List {
            if entries.isEmpty {
                Text("No finished tasks yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries) { entry in
                    row(for: entry)
                }
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func row(for entry: GroundedViewModel.HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.task.title)
                .font(.headline)

            HStack(spacing: 8) {
                Text(statusLabel(for: entry.task.status))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor(for: entry.task.status))

                if let result = entry.result {
                    Text("· \(Int(result.confidence.rounded()))% confidence")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if entry.task.starsEarned > 0 {
                    HStack(spacing: 2) {
                        ForEach(0..<entry.task.starsEarned, id: \.self) { _ in
                            Image(systemName: "star.fill")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.yellow)
                }
            }

            if let result = entry.result {
                Text(result.feedback)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text((entry.task.completedAt ?? entry.task.createdAt).formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func statusLabel(for status: TaskStatus) -> String {
        switch status {
        case .active: return "In progress"
        case .completed: return "Verified"
        case .abandoned: return "Abandoned"
        }
    }

    private func statusColor(for status: TaskStatus) -> Color {
        switch status {
        case .active: return .blue
        case .completed: return .green
        case .abandoned: return .red
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        HistoryView(entries: GroundedViewModel.previewIdle().history)
    }
}
#endif
