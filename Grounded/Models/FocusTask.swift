//
//  FocusTask.swift
//  Grounded
//
//  A single thing the user commits to doing. Named `FocusTask`, NOT `Task`,
//  because `Task` collides with Swift Concurrency's `Task` type.
//

import Foundation

/// Lifecycle of a task. Replaces a bare `isComplete` bool so an abandoned task
/// is distinguishable from a verified one in history.
enum TaskStatus: String, Codable {
    case active
    case completed
    case abandoned
}

struct FocusTask: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var suggestedProof: ProofType
    var createdAt: Date
    /// Set when the task leaves the `.active` state (completed or abandoned).
    var completedAt: Date?
    var status: TaskStatus
    var starsEarned: Int

    init(
        id: UUID = UUID(),
        title: String,
        suggestedProof: ProofType,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        status: TaskStatus = .active,
        starsEarned: Int = 0
    ) {
        self.id = id
        self.title = title
        self.suggestedProof = suggestedProof
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.status = status
        self.starsEarned = starsEarned
    }

    /// Convenience for call sites that only care whether the task was verified.
    var isComplete: Bool { status == .completed }
}
