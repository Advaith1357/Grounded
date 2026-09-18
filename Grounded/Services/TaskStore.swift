//
//  TaskStore.swift
//  Grounded
//
//  Plain JSON persistence. No SwiftData, no Core Data.
//    - tasks.json        [FocusTask]
//    - submissions.json   [ProofSubmission]
//    - progress.json      ProgressState
//    - proofs/<uuid>.jpg|pdf   proof files (kept out of the JSON)
//
//  Everything lives in the app's Documents directory. Load once on init, save
//  after every mutation.
//

import Foundation

/// Lightweight progress model. Named `ProgressState` to avoid colliding with
/// Foundation's `Progress`.
struct ProgressState: Codable, Equatable {
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var totalCharge: Int = 0
    var lastCompletionDate: Date?
}

final class TaskStore {

    private(set) var tasks: [FocusTask] = []
    private(set) var submissions: [ProofSubmission] = []
    private(set) var progress = ProgressState()

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
    private var progressURL: URL { directory.appendingPathComponent("progress.json") }
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
        if let data = try? Data(contentsOf: progressURL),
           let decoded = try? decoder.decode(ProgressState.self, from: data) {
            progress = decoded
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

    /// Insert or replace a task by id.
    func upsert(_ task: FocusTask) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.append(task)
        }
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

    func setProgress(_ newValue: ProgressState) {
        progress = newValue
        persist(progress, to: progressURL)
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
