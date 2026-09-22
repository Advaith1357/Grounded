//
//  ProofType.swift
//  Grounded
//
//  The app now only accepts visual proof — no AI-suggested proof type, no
//  typed/timer proof. The user always has both options for the active task.
//

import Foundation

enum ProofType: String, Codable, Equatable {
    case photo
    case pdf

    var displayName: String {
        switch self {
        case .photo: return "Photo"
        case .pdf: return "PDF Document"
        }
    }

    var sfSymbol: String {
        switch self {
        case .photo: return "camera"
        case .pdf: return "doc.text"
        }
    }
}
