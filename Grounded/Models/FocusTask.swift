//
//  FocusTask.swift
//  Grounded
//
//  A single item in the user-generated task queue. Named `FocusTask`, NOT
//  `Task`, because `Task` collides with Swift Concurrency's `Task` type.
//
//  No `suggestedProof` field anymore: there's no AI classification step at
//  creation time. `proposedProof` is the user's own free-text description of
//  what they intend to submit ("Proposed proof" at creation) — it's passed to
//  Gemini as context when they actually submit a photo or PDF later.
//

import Foundation

enum TaskStatus: String, Codable {
    case queued
    case completed
    case abandoned
}

struct FocusTask: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var proposedProof: String
    var createdAt: Date
    var completedAt: Date?
    var status: TaskStatus

    init(
        id: UUID = UUID(),
        title: String,
        proposedProof: String,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        status: TaskStatus = .queued
    ) {
        self.id = id
        self.title = title
        self.proposedProof = proposedProof
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.status = status
    }
}
