//
//  FriendsService.swift
//  Grounded
//
//  URLSession client for the friends server. Stateless: every call that needs
//  an account takes the bearer token, so the view model owns identity. The
//  server address is read per call so changing it in the Kernel sheet applies
//  immediately.
//

import Foundation

protocol FriendsProviding: Sendable {
    func register(name: String) async throws -> Registration
    func deleteAccount(token: String) async throws
    func updateStatus(_ state: FriendState, unlockEndsAt: Date?, token: String) async throws
    /// Friends (with live status) and pending nudges in one request.
    func sync(token: String) async throws -> SyncResult
    /// Throws unless the server answers its health check.
    func ping() async throws
    func addFriend(code: String, token: String) async throws -> Friend
    func removeFriend(id: String, token: String) async throws
    func sendNudge(to friendID: String, token: String) async throws
    func acknowledgeNudges(ids: [Int], token: String) async throws
}

final class FriendsService: FriendsProviding {

    private let session: URLSession
    private let baseURL: @Sendable () -> String

    init(session: URLSession = .shared, baseURL: @escaping @Sendable () -> String) {
        self.session = session
        self.baseURL = baseURL
    }

    // MARK: - API

    func register(name: String) async throws -> Registration {
        struct Response: Decodable { let id: String; let name: String; let code: String; let token: String }
        let data = try await perform("POST", "/v1/users", body: ["name": name], token: nil)
        let response = try decode(Response.self, from: data)
        return Registration(profile: FriendsProfile(id: response.id, name: response.name, code: response.code), token: response.token)
    }

    func deleteAccount(token: String) async throws {
        _ = try await perform("DELETE", "/v1/me", token: token)
    }

    func updateStatus(_ state: FriendState, unlockEndsAt: Date?, token: String) async throws {
        var body: [String: Any] = ["state": state.rawValue]
        if state == .unlocked, let unlockEndsAt { body["unlockEndsAt"] = unlockEndsAt.timeIntervalSince1970 }
        _ = try await perform("PUT", "/v1/me/status", body: body, token: token)
    }

    func sync(token: String) async throws -> SyncResult {
        try decode(SyncResult.self, from: try await perform("GET", "/v1/sync", token: token))
    }

    func ping() async throws {
        _ = try await perform("GET", "/health", token: nil)
    }

    func addFriend(code: String, token: String) async throws -> Friend {
        struct Response: Decodable { let friend: Friend }
        let data = try await perform("POST", "/v1/friends", body: ["code": code], token: token)
        return try decode(Response.self, from: data).friend
    }

    func removeFriend(id: String, token: String) async throws {
        // Encode as a single path segment (escapes "/" too); `url(for:)` takes
        // the path as already-encoded so it isn't escaped a second time.
        var segmentAllowed = CharacterSet.alphanumerics
        segmentAllowed.insert(charactersIn: "-._~")
        let escaped = id.addingPercentEncoding(withAllowedCharacters: segmentAllowed) ?? id
        _ = try await perform("DELETE", "/v1/friends/\(escaped)", token: token)
    }

    func sendNudge(to friendID: String, token: String) async throws {
        _ = try await perform("POST", "/v1/nudges", body: ["to": friendID], token: token)
    }

    func acknowledgeNudges(ids: [Int], token: String) async throws {
        _ = try await perform("POST", "/v1/nudges/ack", body: ["ids": ids], token: token)
    }

    // MARK: - Transport

    private func url(for path: String) throws -> URL {
        let raw = baseURL().trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: raw),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty else {
            throw FriendsError.invalidServerURL
        }
        var basePath = components.percentEncodedPath
        while basePath.hasSuffix("/") { basePath.removeLast() }
        components.percentEncodedPath = basePath + path
        guard let url = components.url else { throw FriendsError.invalidServerURL }
        return url
    }

    private func perform(_ method: String, _ path: String, body: [String: Any]? = nil, token: String?) async throws -> Data {
        var request = URLRequest(url: try url(for: path), timeoutInterval: 10)
        request.httpMethod = method
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let address = baseURL().trimmingCharacters(in: .whitespacesAndNewlines)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw FriendsError.unreachable(address: address)
        }

        guard let http = response as? HTTPURLResponse else { throw FriendsError.invalidResponse }
        switch http.statusCode {
        case 200..<300:
            return data
        case 401:
            throw FriendsError.unauthorized
        case 429:
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init) ?? 60
            throw FriendsError.rateLimited(retryAfter: retry)
        default:
            struct Failure: Decodable { let error: String }
            let message = (try? JSONDecoder().decode(Failure.self, from: data))?.error
            throw FriendsError.server(message ?? "The friends server returned an error (\(http.statusCode)).")
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw FriendsError.invalidResponse
        }
    }
}
