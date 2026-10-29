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

/// One poll: everything the Grid needs, in a single request.
struct SyncResult: Decodable, Equatable {
    let friends: [Friend]
    let nudges: [Nudge]
}

struct Registration: Equatable {
    let profile: FriendsProfile
    let token: String
}

enum FriendsError: LocalizedError, Equatable {
    case invalidServerURL
    /// The request never got a response. `address` is the server URL we tried.
    case unreachable(address: String)
    case unauthorized
    case rateLimited(retryAfter: TimeInterval)
    case server(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "The friends server address in Settings isn't a valid http(s) URL."
        case .unreachable(let address):
            return Self.unreachableMessage(address: address, onSimulator: Self.runsOnSimulator)
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

    // MARK: - "Can't connect" diagnostics

    static var runsOnSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    /// Says what is probably wrong, not just that something is. The two classic
    /// causes: a physical phone pointed at 127.0.0.1 (which is the phone
    /// itself), and a LAN address when the Local Network permission is off.
    static func unreachableMessage(address: String, onSimulator: Bool) -> String {
        let base = "Can't reach the friends server at \(address)."
        switch AddressKind(address) {
        case .loopback where onSimulator:
            return base + " Is it running? Start it with: python3 Server/server.py"
        case .loopback:
            return base + " On a phone, that address means the phone itself. Set The Grid Server in Settings to your hosted server's address."
        case .privateNetwork:
            return base + " Make sure the phone is on the same Wi-Fi as the server, and that Grounded is allowed under Settings → Privacy & Security → Local Network."
        case .other:
            return base + " Check your connection, and that the server is up and the address in Settings is right."
        }
    }

    enum AddressKind: Equatable {
        case loopback
        case privateNetwork
        case other

        init(_ address: String) {
            // URLComponents reports IPv6 literals with their brackets: "[::1]".
            let host = (URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines))?.host ?? "")
                .lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            if host == "localhost" || host == "::1" || host.hasPrefix("127.") {
                self = .loopback
                return
            }
            let octets = host.split(separator: ".").compactMap { Int($0) }
            if octets.count == 4,
               octets[0] == 10 || (octets[0] == 192 && octets[1] == 168) || (octets[0] == 172 && (16...31).contains(octets[1])) {
                self = .privateNetwork
            } else if host.hasSuffix(".local") {
                self = .privateNetwork
            } else {
                self = .other
            }
        }
    }
}
