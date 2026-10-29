//
//  QueueView.swift
//  Grounded
//
//  Queue tab. Replaces the old Mission Board — no more hardcoded ed-tech
//  sample tasks; this is a plain user-generated list. Single-threaded: only
//  `taskQueue.first` (the Active slot) is interactive. Everything below it is
//  Standby — muted and non-interactive until the Active task resolves.
//
//  Block lists (which apps get blocked) live at the top of this tab: they're
//  the thing you set up while planning your work, so they sit next to the
//  tasks instead of buried in Settings.
//

import SwiftUI

struct QueueView: View {
    @ObservedObject var viewModel: GroundedViewModel

    @State private var showAddTask = false
    @State private var showCamera = false
    @State private var showDocumentPicker = false
    @State private var showAbandonConfirm = false

    @AppStorage(SettingsKey.nightlyLockoutTime) private var lockoutTimeInterval = SettingsKey.defaultLockoutInterval

    /// The user's own maximum, chosen in onboarding (Settings can change it).
    @AppStorage(SettingsKey.dailyLimitMinutes) private var dailyLimitMinutes = DailyLimit.defaultMinutes

    private var voltageEarnedToday: Int {
        let calendar = Calendar.current
        return viewModel.history
            .filter { $0.task.status == .completed }
            .filter { calendar.isDateInToday($0.task.completedAt ?? .distantPast) }
            .count * VerificationResult.flatReward
    }

    private var circuitBreakerTimeText: String {
        Date(timeIntervalSinceReferenceDate: lockoutTimeInterval)
            .formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                stickyHeader

                trickleBanner

                ZStack(alignment: .bottomTrailing) {
                    NexusColor.background.ignoresSafeArea()
                    CircuitBackdrop()

                    ScrollView {
                        VStack(spacing: 20) {
                            BlockListsSection()

                            if viewModel.taskQueue.isEmpty {
                                emptyState
                            } else {
                                taskRows
                            }
                        }
                        .padding(NexusMetrics.screenPadding)
                        .padding(.bottom, 80) // room for the FAB
                    }

                    fab
                }
            }
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showAddTask) {
                AddTaskSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $showCamera) {
                CameraPicker { data in viewModel.submitPhoto(data) }
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showDocumentPicker) {
                DocumentPicker(
                    onPick: { data in viewModel.submitPDF(data) },
                    onError: { message in viewModel.errorMessage = message }
                )
                .ignoresSafeArea()
            }
            .overlay(alignment: .top) {
                if let result = viewModel.lastResult {
                    ResultBanner(result: result) { viewModel.dismissResult() }
                        .padding(.horizontal, NexusMetrics.screenPadding)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.default, value: viewModel.lastResult)
            .confirmationDialog(
                "Abandon this task?",
                isPresented: $showAbandonConfirm,
                titleVisibility: .visible
            ) {
                Button("Abandon (streak resets)", role: .destructive) { viewModel.abandonActiveTask() }
                Button("Keep going", role: .cancel) { }
            }
        }
    }

    private var stickyHeader: some View {
        HStack {
            Text("DAILY LOAD: \(voltageEarnedToday) / \(dailyLimitMinutes) MIN")
                .font(NexusFont.mono(11))
                .foregroundStyle(NexusColor.textSecondary)
            Spacer()
            Text("CIRCUIT BREAKER: \(circuitBreakerTimeText)")
                .font(NexusFont.mono(11))
                .foregroundStyle(NexusColor.textSecondary)
        }
        .padding(.horizontal, NexusMetrics.screenPadding)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(NexusColor.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(NexusColor.border).frame(height: 1)
        }
    }

    /// Always visible, so it's clear whether passive charge is running, why
    /// not, and when the next +1V lands.
    private var trickleBanner: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let status = TrickleSchedule.status(
                queueIsEmpty: viewModel.taskQueue.isEmpty,
                balance: viewModel.economy.voltageBalance,
                lastTrickleAt: viewModel.economy.lastTrickleAt,
                now: timeline.date
            )
            let paused = status == .pausedWhileTaskQueued

            VStack(spacing: 2) {
                HStack(spacing: 8) {
                    Image(systemName: paused ? "pause.fill" : "bolt.fill")
                    Text(Self.trickleHeadline(status, balance: viewModel.economy.voltageBalance))
                        .font(NexusFont.sans(13, weight: .semibold))
                }
                if let detail = Self.trickleDetail(status) {
                    Text(detail)
                        .font(NexusFont.mono(11))
                        .opacity(0.8)
                }
            }
            .foregroundStyle(paused ? NexusColor.textSecondary : NexusColor.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(paused ? NexusColor.surfaceElevated : NexusColor.accent)
        }
    }

    private static func trickleHeadline(_ status: TrickleSchedule.Status, balance: Int) -> String {
        switch status {
        case .pausedWhileTaskQueued: return "Trickle charge paused"
        case .full: return "Trickle Charge full: \(balance)V / \(TrickleSchedule.cap)V"
        case .charging: return "Trickle Charge Active: \(balance)V / \(TrickleSchedule.cap)V"
        }
    }

    private static func trickleDetail(_ status: TrickleSchedule.Status) -> String? {
        switch status {
        case .pausedWhileTaskQueued: return "Charges again once your queue is empty"
        case .full: return nil
        case .charging(let seconds): return "Next +1V in \(TrickleSchedule.countdownText(seconds))"
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(NexusColor.textSecondary)
            Text("Queue is empty")
                .font(NexusFont.sans(18, weight: .bold))
                .foregroundStyle(NexusColor.textPrimary)
            Text("Tap + to define a task.")
                .font(NexusFont.sans(13))
                .foregroundStyle(NexusColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var taskRows: some View {
        VStack(spacing: 12) {
            ForEach(Array(viewModel.taskQueue.enumerated()), id: \.element.id) { index, task in
                if index == 0 {
                    activeCard(for: task)
                } else {
                    standbyRow(for: task)
                }
            }
        }
    }

    private func activeCard(for task: FocusTask) -> some View {
        NexusCard(highlighted: true) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("ACTIVE")
                        .font(NexusFont.mono(11))
                        .foregroundStyle(NexusColor.accent)
                    Spacer()
                    Button {
                        showAbandonConfirm = true
                    } label: {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(NexusColor.textSecondary)
                    }
                }

                Text(task.title)
                    .font(NexusFont.sans(18, weight: .bold))
                    .foregroundStyle(NexusColor.textPrimary)

                if !task.proposedProof.isEmpty {
                    Text(task.proposedProof)
                        .font(NexusFont.sans(13))
                        .foregroundStyle(NexusColor.textSecondary)
                }

                if viewModel.isVerifying {
                    HStack(spacing: 8) {
                        ProgressView().tint(NexusColor.accent)
                        Text("Verifying…")
                            .font(NexusFont.sans(13))
                            .foregroundStyle(NexusColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                } else {
                    HStack(spacing: 12) {
                        Button {
                            showCamera = true
                        } label: {
                            Label("Take Photo", systemImage: "camera")
                                .font(NexusFont.sans(13, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .foregroundStyle(NexusColor.background)
                        .background(NexusColor.accent)
                        .clipShape(RoundedRectangle(cornerRadius: NexusMetrics.chipRadius))

                        Button {
                            showDocumentPicker = true
                        } label: {
                            Label("Upload PDF", systemImage: "doc.text")
                                .font(NexusFont.sans(13, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .foregroundStyle(NexusColor.accent)
                        .background(NexusColor.surfaceElevated)
                        .overlay(RoundedRectangle(cornerRadius: NexusMetrics.chipRadius).stroke(NexusColor.accent))
                        .clipShape(RoundedRectangle(cornerRadius: NexusMetrics.chipRadius))
                    }
                }
            }
        }
    }

    private func standbyRow(for task: FocusTask) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 12))
                .foregroundStyle(NexusColor.textSecondary.opacity(0.6))
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(NexusFont.sans(15, weight: .semibold))
                    .foregroundStyle(NexusColor.textSecondary)
                Text("Standby")
                    .font(NexusFont.mono(10))
                    .foregroundStyle(NexusColor.textSecondary.opacity(0.6))
            }
            Spacer()
        }
        .padding(14)
        .background(NexusColor.surfaceElevated.opacity(0.5))
        .overlay(RoundedRectangle(cornerRadius: NexusMetrics.cardRadius).stroke(NexusColor.border))
        .clipShape(RoundedRectangle(cornerRadius: NexusMetrics.cardRadius))
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                viewModel.deleteStandbyTask(id: task.id)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    private var fab: some View {
        Button {
            showAddTask = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(NexusColor.background)
                .frame(width: 56, height: 56)
                .background(NexusColor.accent)
                .clipShape(Circle())
                .shadow(color: NexusColor.accent.opacity(0.4), radius: 8)
        }
        .padding(20)
    }
}

/// Reports the rendered height of the feedback text, so the expanded view can
/// be exactly as tall as the text (up to a cap) instead of a fixed-size box.
private struct FeedbackHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct ResultBanner: View {
    let result: VerificationResult
    let onDismiss: () -> Void

    @State private var isExpanded = false
    @State private var feedbackHeight: CGFloat = 0

    private static let collapsedLineLimit = 2
    private static let maxExpandedHeight: CGFloat = 280

    /// Roughly what two lines hold at this size; past it the text is cut off.
    private var mayBeTruncated: Bool { result.feedback.count > 70 }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: result.passed ? "checkmark.seal.fill" : "xmark.seal.fill")
                .foregroundStyle(result.passed ? NexusColor.accent : Color(hex: 0xEF4444))
            VStack(alignment: .leading, spacing: 4) {
                Text(result.passed ? "Verified — +\(VerificationResult.flatReward)V" : "Not verified")
                    .font(NexusFont.sans(14, weight: .bold))
                    .foregroundStyle(NexusColor.textPrimary)
                feedback
                if mayBeTruncated {
                    Text(isExpanded ? "TAP TO SHOW LESS" : "TAP TO READ ALL")
                        .font(NexusFont.mono(10, weight: .bold))
                        .foregroundStyle(NexusColor.accent)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard mayBeTruncated else { return }
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .foregroundStyle(NexusColor.textSecondary)
            }
        }
        .padding(14)
        .background(NexusColor.surface)
        .overlay(RoundedRectangle(cornerRadius: NexusMetrics.cardRadius).stroke(result.passed ? NexusColor.accent : Color(hex: 0xEF4444)))
        .clipShape(RoundedRectangle(cornerRadius: NexusMetrics.cardRadius))
        .shadow(radius: 8)
    }

    @ViewBuilder
    private var feedback: some View {
        let text = Text(result.feedback)
            .font(NexusFont.sans(12))
            .foregroundStyle(NexusColor.textSecondary)
            .textSelection(.enabled)

        if isExpanded {
            ScrollView {
                text
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: FeedbackHeightKey.self, value: proxy.size.height)
                    })
            }
            .frame(height: min(max(feedbackHeight, 1), Self.maxExpandedHeight))
            .onPreferenceChange(FeedbackHeightKey.self) { feedbackHeight = $0 }
        } else {
            text.lineLimit(Self.collapsedLineLimit)
        }
    }
}

#if DEBUG
#Preview {
    QueueView(viewModel: .previewQueue())
        .environmentObject(ScreenTimeShieldManager())
}
#endif
