//
//  ProofSubmission.swift
//  Grounded
//
//  One attempt to prove a task is done. The actual proof file (jpg / pdf) lives
//  on disk under Documents/proofs/<uuid>.<ext>; this struct only stores the
//  file name so image/PDF `Data` never lands in the persisted JSON.
//

import Foundation

struct ProofSubmission: Identifiable, Codable, Equatable {
    let id: UUID
    let taskID: UUID
    let type: ProofType
    let submittedAt: Date
    /// File name (not a full path) under Documents/proofs. `nil` for timer proofs,
    /// which have no file.
    var fileName: String?
    /// The judgement, once it comes back. `nil` while verifying.
    var result: VerificationResult?

    init(
        id: UUID = UUID(),
        taskID: UUID,
        type: ProofType,
        submittedAt: Date = Date(),
        fileName: String? = nil,
        result: VerificationResult? = nil
    ) {
        self.id = id
        self.taskID = taskID
        self.type = type
        self.submittedAt = submittedAt
        self.fileName = fileName
        self.result = result
    }
}
