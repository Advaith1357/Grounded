import XCTest

// MARK: - Models

final class FriendModelTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func friend(_ state: FriendState, endsAt: Date?) -> Friend {
        Friend(id: "1", name: "Alex", state: state, unlockEndsAt: endsAt, statusUpdatedAt: now)
    }

    func testUnlockedWithFutureDeadlineIsUnlocked() {
        XCTAssertEqual(friend(.unlocked, endsAt: now.addingTimeInterval(60)).effectiveState(at: now), .unlocked)
    }

    func testExpiredBreakReadsAsGrounded() {
        XCTAssertEqual(friend(.unlocked, endsAt: now.addingTimeInterval(-1)).effectiveState(at: now), .grounded)
        XCTAssertEqual(friend(.unlocked, endsAt: now).effectiveState(at: now), .grounded)
    }

    func testUnlockedWithoutDeadlineReadsAsGrounded() {
        XCTAssertEqual(friend(.unlocked, endsAt: nil).effectiveState(at: now), .grounded)
    }

    func testGroundedStaysGrounded() {
        XCTAssertEqual(friend(.grounded, endsAt: now.addingTimeInterval(600)).effectiveState(at: now), .grounded)
    }
}

// MARK: - Service

private final class StubURLProtocol: URLProtocol {
    struct Stub {
        var status = 200
        var headers: [String: String] = [:]
        var body = Data()
        var error: Error?
    }

    nonisolated(unsafe) static var handler: ((URLRequest, Data?) -> Stub)?
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            stream.close()
            body = data
        }
        Self.lastRequest = request
        Self.lastBody = body

        let stub = Self.handler?(request, body) ?? Stub()
        if let error = stub.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: stub.status, httpVersion: nil, headerFields: stub.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class FriendsServiceTests: XCTestCase {

    private func makeService(baseURL: String = "http://127.0.0.1:8787") -> FriendsService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return FriendsService(session: URLSession(configuration: configuration), baseURL: { baseURL })
    }

    private func json(_ object: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    override func setUp() {
        StubURLProtocol.handler = nil
        StubURLProtocol.lastRequest = nil
        StubURLProtocol.lastBody = nil
    }

    func testRegisterSendsNameWithoutCredentialsAndDecodes() async throws {
        StubURLProtocol.handler = { _, _ in
            .init(status: 201, body: self.json(["id": "u1", "name": "Alex", "code": "K7M2QX", "token": "secret"]))
        }
        let registration = try await makeService().register(name: "Alex")
        XCTAssertEqual(registration, Registration(profile: FriendsProfile(id: "u1", name: "Alex", code: "K7M2QX"), token: "secret"))

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/v1/users")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let body = try XCTUnwrap(StubURLProtocol.lastBody)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: body) as? [String: String], ["name": "Alex"])
    }

    func testSyncSendsBearerTokenAndDecodesFriendsAndNudges() async throws {
        StubURLProtocol.handler = { _, _ in
            .init(body: self.json([
                "friends": [
                    ["id": "2", "name": "Jordan", "state": "unlocked", "unlockEndsAt": 1_000_600.5, "statusUpdatedAt": 1_000_000.0],
                    ["id": "3", "name": "Sam", "state": "grounded", "unlockEndsAt": NSNull(), "statusUpdatedAt": 999_000.0],
                ],
                "nudges": [["id": 7, "fromId": "2", "fromName": "Jordan", "createdAt": 1_000_100.0]],
            ]))
        }
        let result = try await makeService().sync(token: "tok")
        let friends = result.friends
        XCTAssertEqual(StubURLProtocol.lastRequest?.url?.path, "/v1/sync")
        XCTAssertEqual(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertEqual(result.nudges, [Nudge(id: 7, fromId: "2", fromName: "Jordan", createdAt: Date(timeIntervalSince1970: 1_000_100))])
        XCTAssertEqual(friends.map(\.name), ["Jordan", "Sam"])
        XCTAssertEqual(friends[0].state, .unlocked)
        XCTAssertEqual(friends[0].unlockEndsAt, Date(timeIntervalSince1970: 1_000_600.5))
        XCTAssertNil(friends[1].unlockEndsAt)
    }

    func testUpdateStatusIncludesDeadlineOnlyWhenUnlocked() async throws {
        let service = makeService()
        let deadline = Date(timeIntervalSince1970: 2_000_000)

        try await service.updateStatus(.unlocked, unlockEndsAt: deadline, token: "t")
        var body = try JSONSerialization.jsonObject(with: XCTUnwrap(StubURLProtocol.lastBody)) as? [String: Any]
        XCTAssertEqual(StubURLProtocol.lastRequest?.httpMethod, "PUT")
        XCTAssertEqual(body?["state"] as? String, "unlocked")
        XCTAssertEqual(body?["unlockEndsAt"] as? Double, 2_000_000)

        try await service.updateStatus(.grounded, unlockEndsAt: deadline, token: "t")
        body = try JSONSerialization.jsonObject(with: XCTUnwrap(StubURLProtocol.lastBody)) as? [String: Any]
        XCTAssertEqual(body?["state"] as? String, "grounded")
        XCTAssertNil(body?["unlockEndsAt"])
    }

    func testErrorStatusMapping() async {
        let service = makeService()

        StubURLProtocol.handler = { _, _ in .init(status: 401, body: self.json(["error": "x"])) }
        await assertThrows(FriendsError.unauthorized) { _ = try await service.sync(token: "t") }

        StubURLProtocol.handler = { _, _ in .init(status: 429, headers: ["Retry-After": "42"], body: self.json(["error": "slow down"])) }
        await assertThrows(FriendsError.rateLimited(retryAfter: 42)) { try await service.sendNudge(to: "2", token: "t") }

        StubURLProtocol.handler = { _, _ in .init(status: 404, body: self.json(["error": "No one has that friend code."])) }
        await assertThrows(FriendsError.server("No one has that friend code.")) { _ = try await service.addFriend(code: "AAAAAA", token: "t") }

        StubURLProtocol.handler = { _, _ in .init(status: 500, body: Data("<html>".utf8)) }
        await assertThrows(FriendsError.server("The friends server returned an error (500).")) { _ = try await service.sync(token: "t") }

        StubURLProtocol.handler = { _, _ in .init(body: Data("not json".utf8)) }
        await assertThrows(FriendsError.invalidResponse) { _ = try await service.sync(token: "t") }

        StubURLProtocol.handler = { _, _ in .init(error: URLError(.cannotConnectToHost)) }
        await assertThrows(FriendsError.unreachable(address: "http://127.0.0.1:8787")) { _ = try await service.sync(token: "t") }
    }

    func testInvalidServerAddress() async {
        for bad in ["", "not a url", "ftp://example.com", "http://"] {
            await assertThrows(FriendsError.invalidServerURL, "\(bad)") {
                _ = try await self.makeService(baseURL: bad).sync(token: "t")
            }
        }
    }

    func testServerAddressWithPathAndTrailingSlash() async throws {
        StubURLProtocol.handler = { _, _ in .init(body: self.json(["friends": [], "nudges": []])) }
        _ = try await makeService(baseURL: "  https://example.com/api/  ").sync(token: "t")
        XCTAssertEqual(StubURLProtocol.lastRequest?.url?.absoluteString, "https://example.com/api/v1/sync")
    }

    func testPingHitsTheHealthEndpointWithoutCredentials() async throws {
        StubURLProtocol.handler = { _, _ in .init(body: self.json(["ok": true])) }
        try await makeService().ping()
        XCTAssertEqual(StubURLProtocol.lastRequest?.url?.path, "/health")
        XCTAssertNil(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"))

        StubURLProtocol.handler = { _, _ in .init(error: URLError(.timedOut)) }
        await assertThrows(FriendsError.unreachable(address: "http://127.0.0.1:8787")) { try await self.makeService().ping() }
    }

    func testRemoveFriendEscapesTheID() async throws {
        try await makeService().removeFriend(id: "a/b c", token: "t")
        XCTAssertEqual(StubURLProtocol.lastRequest?.httpMethod, "DELETE")
        XCTAssertEqual(StubURLProtocol.lastRequest?.url?.absoluteString, "http://127.0.0.1:8787/v1/friends/a%2Fb%20c")
    }

    private func assertThrows(
        _ expected: FriendsError,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("expected \(expected) \(message)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? FriendsError, expected, message, file: file, line: line)
        }
    }
}

// MARK: - "Can't connect" diagnostics

final class UnreachableMessageTests: XCTestCase {

    func testAddressClassification() {
        for loopback in ["http://127.0.0.1:8787", "http://localhost:8787", "http://127.1.2.3", "http://[::1]:8787"] {
            XCTAssertEqual(FriendsError.AddressKind(loopback), .loopback, loopback)
        }
        for lan in ["http://192.168.1.20:8787", "http://10.0.0.5:8787", "http://172.16.4.1", "http://172.31.255.1", "http://my-mac.local:8787"] {
            XCTAssertEqual(FriendsError.AddressKind(lan), .privateNetwork, lan)
        }
        for other in ["https://grounded.pythonanywhere.com", "http://172.32.0.1", "http://172.15.0.1", "http://8.8.8.8", "garbage", ""] {
            XCTAssertEqual(FriendsError.AddressKind(other), .other, other)
        }
    }

    func testLoopbackOnSimulatorSaysToStartTheServer() {
        let message = FriendsError.unreachableMessage(address: "http://127.0.0.1:8787", onSimulator: true)
        XCTAssertTrue(message.contains("http://127.0.0.1:8787"))
        XCTAssertTrue(message.contains("python3 Server/server.py"))
    }

    func testLoopbackOnAPhoneExplainsThePhoneIsNotYourMac() {
        let message = FriendsError.unreachableMessage(address: "http://127.0.0.1:8787", onSimulator: false)
        XCTAssertTrue(message.contains("the phone itself"))
        XCTAssertFalse(message.contains("python3"))
    }

    func testLANAddressMentionsTheLocalNetworkPermission() {
        let message = FriendsError.unreachableMessage(address: "http://192.168.1.20:8787", onSimulator: false)
        XCTAssertTrue(message.contains("Local Network"))
    }

    func testHostedAddressGivesGenericAdvice() {
        let message = FriendsError.unreachableMessage(address: "https://grounded.pythonanywhere.com", onSimulator: false)
        XCTAssertTrue(message.contains("grounded.pythonanywhere.com"))
        XCTAssertFalse(message.contains("Local Network"))
        XCTAssertFalse(message.contains("python3"))
    }
}
