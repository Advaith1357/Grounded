//
//  FriendsModels.swift
//  Grounded
//
//  Wire models for the friends server (Server/server.py). Foundation only.
//

import Foundation

enum FriendState: String, Codable, Equatable {
    case grounded
    case unlocked
}

/// The signed-in user, as returned by the server. The bearer token is kept
/// separately in the Keychain.
struct FriendsProfile: Codable, Equatable {
    let id: String
    let name: String
    let code: String
}

struct Friend: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let state: FriendState
    let unlockEndsAt: Date?
    let statusUpdatedAt: Date

    /// A friend who went `.unlocked` and then closed the app never reports
    /// back to say the break ended, so an expired deadline reads as grounded.
    func effectiveState(at now: Date = Date()) -> FriendState {
        guard state == .unlocked, let endsAt = unlockEndsAt, endsAt > now else { return .grounded }
        return .unlocked
    }
}

struct Nudge: Codable, Identifiable, Equatable {
    let id: Int
    let fromId: String
    let fromName: String
    let createdAt: Date
}

struct Registration: Equatable {
    let profile: FriendsProfile
    let token: String
}

enum FriendsError: LocalizedError, Equatable {
    case invalidServerURL
    case unreachable
    case unauthorized
    case rateLimited(retryAfter: TimeInterval)
    case server(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "The friends server address in Settings isn't a valid http(s) URL."
        case .unreachable:
            return "Can't reach the friends server. Check your connection and the server address in Settings."
        case .unauthorized:
            return "Your Grid account is no longer valid. Join again to keep playing with friends."
        case .rateLimited:
            return "Easy — you nudged them a moment ago."
        case .server(let message):
            return message
        case .invalidResponse:
            return "The friends server sent something unexpected."
        }
    }
}
