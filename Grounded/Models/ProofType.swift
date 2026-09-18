//
//  ProofType.swift
//  Grounded
//
//  The kind of evidence that would demonstrate a task is genuinely done.
//  The AI classifier picks one of these for each task the user states.
//

import Foundation

enum ProofType: Equatable, Hashable {
    /// A photograph of finished physical / handwritten work.
    case photo
    /// A PDF document whose contents show the work is done.
    case pdf
    /// A focused, timed session. Carries an AI-suggested duration in minutes.
    case timer(minutes: Int)

    /// Short human-readable name for buttons and labels.
    var displayName: String {
        switch self {
        case .photo: return "Photo"
        case .pdf: return "PDF Document"
        case .timer: return "Timed Session"
        }
    }

    /// SF Symbol name for icons.
    var sfSymbol: String {
        switch self {
        case .photo: return "camera"
        case .pdf: return "doc.text"
        case .timer: return "timer"
        }
    }

    /// One sentence telling the user what to submit.
    var explanation: String {
        switch self {
        case .photo:
            return "Take a photo that clearly shows the finished work."
        case .pdf:
            return "Upload a PDF whose contents show the task is complete."
        case .timer(let minutes):
            return "Stay in a focused session for \(minutes) minutes."
        }
    }
}

// MARK: - Codable (manual, because the .timer case carries a value)

extension ProofType: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case minutes
    }

    private enum Kind: String, Codable {
        case photo
        case pdf
        case timer
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .photo:
            self = .photo
        case .pdf:
            self = .pdf
        case .timer:
            let minutes = try container.decode(Int.self, forKey: .minutes)
            self = .timer(minutes: minutes)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .photo:
            try container.encode(Kind.photo, forKey: .kind)
        case .pdf:
            try container.encode(Kind.pdf, forKey: .kind)
        case .timer(let minutes):
            try container.encode(Kind.timer, forKey: .kind)
            try container.encode(minutes, forKey: .minutes)
        }
    }
}
