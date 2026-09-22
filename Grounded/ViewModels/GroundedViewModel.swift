//
//  GroundedViewModel.swift
//  Grounded
//
//  The one object the UI talks to. Owns the store, the Gemini actor, and the
//  shield; all three are injected so previews and future swaps are trivial.
//
//  This is the MVP pivot: no more phase state machine, no more full-screen
//  mission flow. The queue and the shield are independent — completing a task
//  never touches the shield, and Discharge/Re-Ground never touch the queue.
//
//  Flow:
//    addTask(title:proposedProof:) -> appended to the queue (no network call)
//    submitPhoto / submitPDF on the ACTIVE task (taskQueue.first) only -> verify
//       pass -> mark complete, +10V flat, streak += 1
//       fail -> surface feedback, task stays active for a retry
//    abandonActiveTask() -> marks abandoned, resets streak, no Voltage penalty
//    discharge(amount:) -> spend Voltage, shield.unlock(), starts an unlock countdown
//    reGround() -> shield.ground() early, or automatically when the countdown ends
//    Trickle charge -> while the queue is empty, +1V every 5 minutes, capped at 20V
//

import Foundation

@MainActor
final class GroundedViewModel: ObservableObject {

    struct HistoryEntry: Identifiable {
        let task: FocusTask
        let result: VerificationResult?
        var id: UUID { task.id }
    }

    // MARK: - Published

    /// In queue order; `taskQueue.first` is the only interactive ("Active") one.
    @Published private(set) var taskQueue: [FocusTask] = []
    @Published private(set) var history: [HistoryEntry] = []
    @Published private(set) var economy = EconomyState()
    @Published private(set) var shieldState: ShieldState = .grounded
    /// Seconds left in the current Discharge break; 0 while grounded.
    @Published private(set) var unlockRemaining: TimeInterval = 0
    @Published private(set) var isVerifying = false
    /// The most recent verification outcome, shown as a dismissible banner in Queue.
    @Published var lastResult: VerificationResult?
    @Published var errorMessage: String?

    private static let trickleInterval: TimeInterval = 5 * 60
    private static let trickleCap = 20

    // MARK: - Dependencies

    private let store: TaskStore
    private let gemini: GeminiProviding
    let shield: ShieldManager

    private var tickTimer: Timer?

    // MARK: - Init

    init(
        store: TaskStore = TaskStore(),
        gemini: GeminiProviding = GeminiService(),
        shield: ShieldManager = MockShieldManager()
    ) {
        self.store = store
        self.gemini = gemini
        self.shield = shield

        rebuildFromStore()

        // Resume an in-progress Discharge break across launches, or clear a
        // stale one that expired while the app was closed.
        if let endsAt = economy.unlockEndsAt, endsAt > Date() {
            shield.unlock()
            shieldState = .unlocked
        } else {
            if economy.unlockEndsAt != nil {
                var e = economy
                e.unlockEndsAt = nil
                store.setEconomy(e)
                economy = e
            }
            shield.ground()
            shieldState = .grounded
        }

        tick()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    deinit {
        tickTimer?.invalidate()
    }

    // MARK: - Queue

    func addTask(title: String, proposedProof: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        let task = FocusTask(
            title: trimmedTitle,
            proposedProof: proposedProof.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        store.upsert(task)
        rebuildFromStore()
    }

    /// Swipe-to-delete for a Standby row. The Active row (index 0) can't be
    /// deleted this way — use `abandonActiveTask()`, which keeps a history record.
    func deleteStandbyTask(id: UUID) {
        guard id != taskQueue.first?.id else { return }
        store.removeTask(id: id)
        rebuildFromStore()
    }

    /// The manual-override path for the Active task: always available, resets
    /// the streak, but — unlike the old build — costs no Voltage. Nothing in
    /// this refactor's economy spec calls for an abandon penalty.
    func abandonActiveTask() {
        guard var task = taskQueue.first else { return }
        task.status = .abandoned
        task.completedAt = Date()
        store.upsert(task)

        var e = store.economy
        e.currentStreak = 0
        store.setEconomy(e)

        rebuildFromStore()
        resetTrickleBaselineIfQueueEmpty()
    }

    // MARK: - Submit proofs (Active task only)

    func submitPhoto(_ imageData: Data) {
        guard let task = taskQueue.first else { return }
        errorMessage = nil
        isVerifying = true

        Task {
            do {
                let fileName = try store.saveProofData(imageData, fileExtension: "jpg")
                let result = try await activeProvider().verifyPhoto(task: task, imageData: imageData)
                record(task: task, submissionType: .photo, fileName: fileName, result: result)
            } catch {
                isVerifying = false
                errorMessage = Self.message(for: error)
            }
        }
    }

    func submitPDF(_ pdfData: Data) {
        guard let task = taskQueue.first else { return }
        errorMessage = nil
        isVerifying = true

        Task {
            do {
                let fileName = try store.saveProofData(pdfData, fileExtension: "pdf")
                let result = try await activeProvider().verifyPDF(task: task, pdfData: pdfData)
                record(task: task, submissionType: .pdf, fileName: fileName, result: result)
            } catch {
                isVerifying = false
                errorMessage = Self.message(for: error)
            }
        }
    }

    /// "Mock AI Mode" (Kernel settings) swaps in the canned provider so UI
    /// testing never spends a real Gemini call.
    private func activeProvider() -> GeminiProviding {
        UserDefaults.standard.bool(forKey: SettingsKey.mockAIMode) ? FakeGeminiService() : gemini
    }

    private func record(task: FocusTask, submissionType: ProofType, fileName: String?, result: VerificationResult) {
        let submission = ProofSubmission(taskID: task.id, type: submissionType, fileName: fileName, result: result)
        store.upsert(submission)

        if result.passed {
            var updated = task
            updated.status = .completed
            updated.completedAt = Date()
            store.upsert(updated)

            var e = store.economy
            e.voltageBalance += VerificationResult.flatReward
            e.currentStreak += 1
            e.longestStreak = max(e.longestStreak, e.currentStreak)
            e.lastCompletionDate = Date()
            store.setEconomy(e)
        }

        isVerifying = false
        lastResult = result
        rebuildFromStore()
        resetTrickleBaselineIfQueueEmpty()
    }

    func dismissResult() {
        lastResult = nil
    }

    // MARK: - Shield: Discharge / Re-Ground

    /// Spend Voltage for a timed break. 1V = 1 minute, so `amount` is both the
    /// cost and the break length in minutes.
    func discharge(amount: Int) {
        guard shieldState == .grounded, economy.voltageBalance >= amount else { return }
        var e = economy
        e.voltageBalance -= amount
        e.unlockEndsAt = Date().addingTimeInterval(TimeInterval(amount * 60))
        store.setEconomy(e)
        economy = e

        shield.unlock()
        shieldState = .unlocked
        updateUnlockRemaining()
    }

    /// Ends the break early, or is called automatically when the countdown hits
    /// 0. Any unused minutes (only possible when ending early) are refunded
    /// back to the balance — `discharge` already deducted the full amount
    /// up front, so this just credits back what wasn't spent.
    func reGround() {
        var e = economy
        if let endsAt = e.unlockEndsAt {
            let unusedMinutes = Int(max(0, endsAt.timeIntervalSinceNow) / 60)
            e.voltageBalance += unusedMinutes
        }
        e.unlockEndsAt = nil
        store.setEconomy(e)
        economy = e

        shield.ground()
        shieldState = .grounded
        unlockRemaining = 0
    }

    // MARK: - Trickle charge (passive generator while the queue is empty)

    private func tick() {
        catchUpTrickle()
        updateUnlockRemaining()
    }

    private func catchUpTrickle() {
        guard taskQueue.isEmpty else { return }
        let elapsed = Date().timeIntervalSince(economy.lastTrickleAt)
        let wholeTicks = Int(elapsed / Self.trickleInterval)
        guard wholeTicks > 0 else { return }

        var e = economy
        let room = max(0, Self.trickleCap - e.voltageBalance)
        let toAdd = min(wholeTicks, room)
        if toAdd > 0 {
            e.voltageBalance += toAdd
        }
        e.lastTrickleAt = e.lastTrickleAt.addingTimeInterval(Double(wholeTicks) * Self.trickleInterval)
        store.setEconomy(e)
        economy = e
    }

    private func resetTrickleBaselineIfQueueEmpty() {
        guard taskQueue.isEmpty else { return }
        var e = economy
        e.lastTrickleAt = Date()
        store.setEconomy(e)
        economy = e
    }

    private func updateUnlockRemaining() {
        guard let endsAt = economy.unlockEndsAt else {
            unlockRemaining = 0
            return
        }
        let remaining = endsAt.timeIntervalSinceNow
        if remaining <= 0 {
            reGround()
        } else {
            unlockRemaining = remaining
        }
    }

    // MARK: - Settings helpers

    /// `false` while neither the Keychain nor Secrets.swift has a real key.
    var geminiKeyConfigured: Bool {
        if let key = KeychainStore.loadGeminiAPIKey(), !key.isEmpty { return true }
        let fallback = Secrets.geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return !fallback.isEmpty && fallback != "PASTE_YOUR_KEY_HERE"
    }

    // MARK: - Helpers

    private func rebuildFromStore() {
        taskQueue = store.tasks
            .filter { $0.status == .queued }
            .sorted { $0.createdAt < $1.createdAt }

        history = store.tasks
            .filter { $0.status != .queued }
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
            .map { task in HistoryEntry(task: task, result: store.latestSubmission(forTaskID: task.id)?.result) }

        economy = store.economy
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

/// UserDefaults keys shared between the Kernel settings sheet, Queue's sticky
/// header, and the view model.
enum SettingsKey {
    static let mockAIMode = "settings.mockAIMode"
    static let nightlyLockoutTime = "settings.nightlyLockoutTime"

    /// 10:00 PM today, encoded as `timeIntervalSinceReferenceDate` (only the
    /// time-of-day portion is ever read back out via `.hourAndMinute`/`.shortened`).
    static var defaultLockoutInterval: Double {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 22
        components.minute = 0
        return calendar.date(from: components)?.timeIntervalSinceReferenceDate ?? 0
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

    /// Empty queue, some banked Voltage, a completed + an abandoned task in history.
    static func previewIdle() -> GroundedViewModel {
        let store = previewStore()

        var done = FocusTask(title: "Finish matrices homework", proposedProof: "A photo of the worked page.", status: .completed)
        done.completedAt = Date().addingTimeInterval(-3600)
        store.upsert(done)
        store.upsert(ProofSubmission(
            taskID: done.id, type: .photo, fileName: "sample.jpg",
            result: VerificationResult(passed: true, confidence: 93, feedback: "All ten problems are worked through by hand.")
        ))

        var bailed = FocusTask(title: "Read the biology chapter", proposedProof: "N/A", status: .abandoned)
        bailed.completedAt = Date().addingTimeInterval(-7200)
        store.upsert(bailed)

        store.setEconomy(EconomyState(voltageBalance: 34, lastTrickleAt: Date(), unlockEndsAt: nil, currentStreak: 1, longestStreak: 4, lastCompletionDate: Date()))

        return GroundedViewModel(store: store, gemini: FakeGeminiService(), shield: MockShieldManager())
    }

    /// A 2-item queue: one Active, one Standby.
    static func previewQueue() -> GroundedViewModel {
        let store = previewStore()
        store.upsert(FocusTask(title: "Finish matrices homework", proposedProof: "Photo of the worked page"))
        store.upsert(FocusTask(title: "Write the lab report", proposedProof: "PDF export from Pages"))
        store.setEconomy(EconomyState(voltageBalance: 12, lastTrickleAt: Date(), unlockEndsAt: nil, currentStreak: 2, longestStreak: 4, lastCompletionDate: Date()))
        return GroundedViewModel(store: store, gemini: FakeGeminiService(), shield: MockShieldManager())
    }

    /// Mid-Discharge break.
    static func previewUnlocked() -> GroundedViewModel {
        let store = previewStore()
        store.setEconomy(EconomyState(voltageBalance: 15, lastTrickleAt: Date(), unlockEndsAt: Date().addingTimeInterval(600), currentStreak: 0, longestStreak: 2, lastCompletionDate: nil))
        return GroundedViewModel(store: store, gemini: FakeGeminiService(), shield: MockShieldManager())
    }
}
#endif
