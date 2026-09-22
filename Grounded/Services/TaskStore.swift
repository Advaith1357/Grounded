//
//  TaskStore.swift
//  Grounded
//
//  Plain JSON persistence. No SwiftData, no Core Data.
//    - tasks.json        [FocusTask]  (the queue + history, distinguished by .status)
//    - submissions.json   [ProofSubmission]
//    - economy.json        EconomyState (Voltage balance, trickle-charge, unlock countdown, streak)
//    - proofs/<uuid>.jpg|pdf   proof files (kept out of the JSON)
//
//  Everything lives in the app's Documents directory. Load once on init, save
//  after every mutation.
//

import Foundation

/// The Voltage economy + shield-unlock state, persisted so it survives relaunch.
/// Named `EconomyState` (not `ProgressState`) since this refactor is about the
/// Voltage economy specifically, not generic "progress".
struct EconomyState: Codable, Equatable {
    /// Banked Voltage. 1V = 1 minute of screen time.
    var voltageBalance: Int = 0
    /// Wall-clock baseline for the trickle-charge generator (see
    /// GroundedViewModel.catchUpTrickle). Reset to `Date()` whenever the queue
    /// transitions from non-empty to empty, so only idle time counts.
    var lastTrickleAt: Date = Date()
    /// When the current Discharge break ends and the shield re-grounds itself.
    /// `nil` while grounded.
    var unlockEndsAt: Date?
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var lastCompletionDate: Date?
}

final class TaskStore {

    private(set) var tasks: [FocusTask] = []
    private(set) var submissions: [ProofSubmission] = []
    private(set) var economy = EconomyState()

    private let directory: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// - Parameter directory: where to read/write. Defaults to Documents.
    ///   Previews pass a throwaway temp directory.
    init(directory: URL? = nil) {
        self.directory = directory
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        createDirectoriesIfNeeded()
        load()
    }

    // MARK: - Paths

    private var tasksURL: URL { directory.appendingPathComponent("tasks.json") }
    private var submissionsURL: URL { directory.appendingPathComponent("submissions.json") }
    private var economyURL: URL { directory.appendingPathComponent("economy.json") }
    private var proofsDirectory: URL { directory.appendingPathComponent("proofs", isDirectory: true) }

    private func createDirectoriesIfNeeded() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: proofsDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Load / save

    private func load() {
        if let data = try? Data(contentsOf: tasksURL),
           let decoded = try? decoder.decode([FocusTask].self, from: data) {
            tasks = decoded
        }
        if let data = try? Data(contentsOf: submissionsURL),
           let decoded = try? decoder.decode([ProofSubmission].self, from: data) {
            submissions = decoded
        }
        if let data = try? Data(contentsOf: economyURL),
           let decoded = try? decoder.decode(EconomyState.self, from: data) {
            economy = decoded
        }
    }

    private func persist<T: Encodable>(_ value: T, to url: URL) {
        do {
            let data = try encoder.encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            print("[TaskStore] Failed to write \(url.lastPathComponent): \(error)")
        }
    }

    // MARK: - Mutations (each one saves)

    /// Insert, replace, or (if `remove` is true) delete a task by id.
    func upsert(_ task: FocusTask) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.append(task)
        }
        persist(tasks, to: tasksURL)
    }

    func removeTask(id: UUID) {
        tasks.removeAll { $0.id == id }
        persist(tasks, to: tasksURL)
    }

    /// Insert or replace a submission by id.
    func upsert(_ submission: ProofSubmission) {
        if let index = submissions.firstIndex(where: { $0.id == submission.id }) {
            submissions[index] = submission
        } else {
            submissions.append(submission)
        }
        persist(submissions, to: submissionsURL)
    }

    func setEconomy(_ newValue: EconomyState) {
        economy = newValue
        persist(economy, to: economyURL)
    }

    // MARK: - Proof files

    /// Writes proof data to Documents/proofs/<uuid>.<ext> and returns the file name.
    func saveProofData(_ data: Data, fileExtension ext: String) throws -> String {
        let name = "\(UUID().uuidString).\(ext)"
        try data.write(to: proofsDirectory.appendingPathComponent(name), options: .atomic)
        return name
    }

    /// Full URL for a stored proof file name.
    func proofFileURL(named name: String) -> URL {
        proofsDirectory.appendingPathComponent(name)
    }

    // MARK: - Queries

    /// The most recent submission recorded for a task, if any.
    func latestSubmission(forTaskID id: UUID) -> ProofSubmission? {
        submissions
            .filter { $0.taskID == id }
            .max(by: { $0.submittedAt < $1.submittedAt })
    }
}
