//
//  GroundedViewModel.swift
//  Grounded
//
//  The one object the UI talks to. Owns the store, the Gemini actor and the
//  app blocker; all three are injected so previews and future swaps are trivial.
//
//  Flow:
//    startTask(title:) -> classify -> set active -> blocker.block()
//    submitPhoto / submitPDF / completeTimer -> verify
//       pass -> mark complete, award charge + stars, blocker.unblock()
//       fail -> surface feedback, keep task active for a retry
//    abandonTask() -> unblock, mark abandoned, reset streak, -50 charge
//

import Foundation
import SwiftUI

@MainActor
final class GroundedViewModel: ObservableObject {

    // MARK: - Phase state machine (drives ContentView)

    enum Phase: Equatable {
        case idle
        case classifying
        case active
        case verifying
        case result(VerificationResult)
    }

    // MARK: - History row (task joined with its latest judgement)

    struct HistoryEntry: Identifiable {
        let task: FocusTask
        let result: VerificationResult?
        var id: UUID { task.id }
    }

    // MARK: - Published

    @Published private(set) var activeTask: FocusTask?
    @Published private(set) var history: [HistoryEntry] = []
    @Published private(set) var progress = ProgressState()
    @Published private(set) var phase: Phase = .idle
    /// Mirror of `blocker.isBlocking`. The blocker is the source of truth; this
    /// exists so SwiftUI has something to observe without the blocker's type.
    @Published private(set) var isBlocking = false
    @Published var errorMessage: String?

    /// `false` while Secrets.swift still holds the placeholder key.
    let geminiKeyConfigured: Bool

    // MARK: - Dependencies

    private let store: TaskStore
    private let gemini: GeminiProviding
    let blocker: AppBlocker

    // MARK: - Init

    init(
        store: TaskStore = TaskStore(),
        gemini: GeminiProviding = GeminiService(),
        blocker: AppBlocker = MockAppBlocker()
    ) {
        self.store = store
        self.gemini = gemini
        self.blocker = blocker

        let key = Secrets.geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.geminiKeyConfigured = !key.isEmpty && key != "PASTE_YOUR_KEY_HERE"

        rebuildFromStore()

        // Restore an in-progress task across launches.
        if let active = store.tasks.first(where: { $0.status == .active }) {
            activeTask = active
            setBlocking(true)
            phase = .active
        }
    }

    // MARK: - Blocked-app names

    func setBlockedApps(from rawText: String) {
        let names = rawText
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        blocker.blockedAppNames = names
    }

    // MARK: - Start

    func startTask(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard activeTask == nil else { return }

        errorMessage = nil
        phase = .classifying

        Task {
            do {
                let proof = try await gemini.classify(taskTitle: trimmed)
                let task = FocusTask(title: trimmed, suggestedProof: proof, status: .active)
                store.upsert(task)
                activeTask = task
                setBlocking(true)
                phase = .active
            } catch {
                phase = .idle
                errorMessage = Self.message(for: error)
            }
        }
    }

    // MARK: - Submit proofs

    func submitPhoto(_ imageData: Data) {
        guard let task = activeTask else { return }
        errorMessage = nil
        phase = .verifying

        Task {
            do {
                let fileName = try store.saveProofData(imageData, fileExtension: "jpg")
                let result = try await gemini.verifyPhoto(task: task, imageData: imageData)
                record(submissionType: .photo, fileName: fileName, result: result)
            } catch {
                phase = .active
                errorMessage = Self.message(for: error)
            }
        }
    }

    func submitPDF(_ pdfData: Data) {
        guard let task = activeTask else { return }
        errorMessage = nil
        phase = .verifying

        Task {
            do {
                let fileName = try store.saveProofData(pdfData, fileExtension: "pdf")
                let result = try await gemini.verifyPDF(task: task, pdfData: pdfData)
                record(submissionType: .pdf, fileName: fileName, result: result)
            } catch {
                phase = .active
                errorMessage = Self.message(for: error)
            }
        }
    }

    /// Timer proofs are judged locally — no API call. `elapsed` is seconds spent
    /// focused; `plannedMinutes` is the suggested duration.
    func completeTimer(elapsed: TimeInterval, plannedMinutes: Int) {
        guard activeTask != nil else { return }

        let target = TimeInterval(max(plannedMinutes, 1) * 60)
        let fraction = min(max(elapsed / target, 0), 1)
        let confidence = (fraction * 100).rounded()
        let passed = elapsed >= target

        let feedback: String
        if passed {
            feedback = "Completed the full \(plannedMinutes)-minute focus session."
        } else {
            feedback = "Ended early — \(Int(confidence))% of the \(plannedMinutes)-minute session done."
        }

        let result = VerificationResult(passed: passed, confidence: confidence, feedback: feedback)
        record(submissionType: .timer(minutes: plannedMinutes), fileName: nil, result: result)
    }

    // MARK: - Result handling

    /// Persist a submission and, on a pass, complete the task and pay out.
    private func record(submissionType: ProofType, fileName: String?, result: VerificationResult) {
        guard var task = activeTask else { return }

        let submission = ProofSubmission(
            taskID: task.id,
            type: submissionType,
            fileName: fileName,
            result: result
        )
        store.upsert(submission)

        if result.passed {
            task.status = .completed
            task.completedAt = Date()
            task.starsEarned = result.stars
            store.upsert(task)

            var updated = store.progress
            updated.totalCharge += VerificationResult.chargeAward(forConfidence: result.confidence)
            updated.currentStreak += 1
            updated.longestStreak = max(updated.longestStreak, updated.currentStreak)
            updated.lastCompletionDate = Date()
            store.setProgress(updated)

            setBlocking(false)
            activeTask = nil
        }

        rebuildFromStore()
        phase = .result(result)
    }

    /// Continue button on the result screen.
    func acknowledgeResult() {
        phase = (activeTask == nil) ? .idle : .active
    }

    // MARK: - Abandon (manual override — always available, never free)

    func abandonTask() {
        guard var task = activeTask else { return }

        task.status = .abandoned
        task.completedAt = Date()
        store.upsert(task)

        var updated = store.progress
        updated.currentStreak = 0
        updated.totalCharge = max(0, updated.totalCharge - 50) // clamped so charge can't go negative
        store.setProgress(updated)

        setBlocking(false)
        activeTask = nil
        rebuildFromStore()
        phase = .idle
    }

    // MARK: - Helpers

    private func setBlocking(_ shouldBlock: Bool) {
        if shouldBlock {
            blocker.block()
        } else {
            blocker.unblock()
        }
        isBlocking = blocker.isBlocking
    }

    private func rebuildFromStore() {
        progress = store.progress
        history = store.tasks
            .filter { $0.status != .active }
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
            .map { task in
                HistoryEntry(task: task, result: store.latestSubmission(forTaskID: task.id)?.result)
            }
    }

    private static func message(for error: Error) -> String {
        if let gemini = error as? GeminiService.GeminiError {
            return gemini.errorDescription ?? "Something went wrong talking to Gemini."
        }
        if error is URLError {
            return "Couldn't reach Gemini. Check your internet connection and try again."
        }
        return error.localizedDescription
    }
}

// MARK: - Preview fixtures

#if DEBUG
extension GroundedViewModel {

    private static func previewStore() -> TaskStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GroundedPreview-\(UUID().uuidString)", isDirectory: true)
        return TaskStore(directory: dir)
    }

    /// Idle home screen with some fake history and progress.
    static func previewIdle() -> GroundedViewModel {
        let store = previewStore()

        var done = FocusTask(title: "Finish matrices homework", suggestedProof: .photo, status: .completed)
        done.completedAt = Date().addingTimeInterval(-3600)
        done.starsEarned = 3
        store.upsert(done)
        store.upsert(ProofSubmission(
            taskID: done.id, type: .photo, fileName: "sample.jpg",
            result: VerificationResult(passed: true, confidence: 93, feedback: "All ten problems are worked through by hand.")
        ))

        var bailed = FocusTask(title: "Read 20 pages of the biology text", suggestedProof: .timer(minutes: 30), status: .abandoned)
        bailed.completedAt = Date().addingTimeInterval(-7200)
        store.upsert(bailed)

        store.setProgress(ProgressState(currentStreak: 1, longestStreak: 4, totalCharge: 275, lastCompletionDate: Date()))

        return GroundedViewModel(store: store, gemini: FakeGeminiService(), blocker: MockAppBlocker())
    }

    /// Mid-task, apps "blocked".
    static func previewActive() -> GroundedViewModel {
        let store = previewStore()
        let vm = GroundedViewModel(
            store: store,
            gemini: FakeGeminiService(classifyResult: .photo),
            blocker: MockAppBlocker()
        )
        vm.startTask(title: "Finish matrices homework")
        return vm
    }
}
#endif
