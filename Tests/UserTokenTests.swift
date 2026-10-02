import XCTest
@testable import RiviumPush

/// Builds an unsigned JWT-shaped token; the SDK only reads the payload.
private func makeToken(sub: String? = "u1", exp: TimeInterval? = nil, tag: String = "sig") -> String {
    var payload: [String: Any] = ["pid": "p1"]
    if let sub = sub { payload["sub"] = sub }
    if let exp = exp { payload["exp"] = exp }
    let data = try! JSONSerialization.data(withJSONObject: payload)
    let body = data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return "eyJhbGciOiJFUzI1NiJ9.\(body).\(tag)"
}

private struct ProviderError: Error {}

/// In-memory stand-in for the Keychain that can be made to fail.
private final class MemoryTokenStore: UserTokenStore {
    var token: String?
    var failReads = false
    var failWrites = false
    var failRemoves = false
    private(set) var writes = 0

    func read() -> String? { failReads ? nil : token }

    @discardableResult
    func write(_ token: String) -> Bool {
        guard !failWrites else { return false }
        self.token = token
        writes += 1
        return true
    }

    @discardableResult
    func remove() -> Bool {
        guard !failRemoves else { return false }
        token = nil
        return true
    }
}

/// Thread-safe counter / box for provider calls made off the main thread.
private final class Locked<T> {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
    func update(_ change: (inout T) -> Void) { lock.lock(); change(&stored); lock.unlock() }
}

final class UserTokenManagerTests: XCTestCase {
    private let base: TimeInterval = 1_800_000_000

    private func get(_ manager: UserTokenManager, file: StaticString = #filePath, line: UInt = #line) -> String? {
        let done = expectation(description: "token")
        var result: String?
        manager.get { result = $0; done.fulfill() }
        wait(for: [done], timeout: 5)
        return result
    }

    private func refresh(_ manager: UserTokenManager) -> String? {
        let done = expectation(description: "refresh")
        var result: String?
        manager.refresh { result = $0; done.fulfill() }
        wait(for: [done], timeout: 5)
        return result
    }

    func testCachesTokenUntilCloseToExpiry() {
        let clock = Locked(Date(timeIntervalSince1970: base))
        let calls = Locked(0)
        let manager = UserTokenManager(
            provider: {
                calls.update { $0 += 1 }
                return makeToken(exp: self.base + 90, tag: "t\(calls.value)")
            },
            now: { clock.value }
        )

        let first = get(manager)
        XCTAssertNotNil(first)
        XCTAssertEqual(get(manager), first)
        XCTAssertEqual(calls.value, 1)

        // 61 s before exp: still reused.
        clock.value = Date(timeIntervalSince1970: base + 29)
        XCTAssertEqual(get(manager), first)
        XCTAssertEqual(calls.value, 1)

        // Inside the 60 s margin: fetched again.
        clock.value = Date(timeIntervalSince1970: base + 31)
        XCTAssertNotEqual(get(manager), first)
        XCTAssertEqual(calls.value, 2)
    }

    func testTokenWithoutExpIsReused() {
        let calls = Locked(0)
        let manager = UserTokenManager(provider: {
            calls.update { $0 += 1 }
            return "opaque-token"
        })
        XCTAssertEqual(get(manager), "opaque-token")
        XCTAssertEqual(get(manager), "opaque-token")
        XCTAssertEqual(calls.value, 1)
    }

    func testConcurrentCallersShareOneProviderCall() {
        let calls = Locked(0)
        let pending = Locked<[(Result<String?, Error>) -> Void]>([])
        let manager = UserTokenManager()
        manager.setCallbackProvider { completion in
            calls.update { $0 += 1 }
            pending.update { $0.append(completion) }
        }

        let results = Locked<[String?]>([])
        let all = expectation(description: "all callers")
        all.expectedFulfillmentCount = 5
        for _ in 0..<5 {
            manager.get { token in
                results.update { $0.append(token) }
                all.fulfill()
            }
        }

        // Let the provider be invoked, then answer it.
        let asked = expectation(description: "provider asked")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { asked.fulfill() }
        wait(for: [asked], timeout: 2)
        XCTAssertEqual(calls.value, 1)
        pending.value.first?(.success("shared"))

        wait(for: [all], timeout: 5)
        XCTAssertEqual(calls.value, 1)
        XCTAssertEqual(results.value.count, 5)
        XCTAssertTrue(results.value.allSatisfy { $0 == "shared" })
    }

    func testRefreshForcesNewFetchAndClearForgets() {
        let calls = Locked(0)
        let manager = UserTokenManager(provider: {
            calls.update { $0 += 1 }
            return "token-\(calls.value)"
        })
        XCTAssertEqual(get(manager), "token-1")
        XCTAssertEqual(refresh(manager), "token-2")
        XCTAssertEqual(get(manager), "token-2")
        XCTAssertEqual(calls.value, 2)

        manager.clear()
        XCTAssertNil(manager.current())
        XCTAssertEqual(get(manager), "token-3")
    }

    func testBadTokensNeverThrow() {
        for bad in ["", "garbage", "a.b.c", "a.!!!.c", "..", "a.eyJleHAiOiJub3BlIn0.c", "a.W10.c"] {
            let claims = UserTokenClaims.read(bad)
            XCTAssertNil(claims.expiresAt, bad)
            XCTAssertNil(claims.subject, bad)
        }
        let claims = UserTokenClaims.read(makeToken(sub: "user-7", exp: base))
        XCTAssertEqual(claims.subject, "user-7")
        XCTAssertEqual(claims.expiresAt, Date(timeIntervalSince1970: base))
    }

    func testProviderFailureGivesNoTokenAndIsReported() {
        let failures = Locked(0)
        let manager = UserTokenManager(provider: { throw ProviderError() })
        manager.onProviderFailure = { _ in failures.update { $0 += 1 } }
        XCTAssertNil(get(manager))
        XCTAssertEqual(failures.value, 1)
    }

    func testSignedOutIsNotAFailure() {
        let failures = Locked(0)
        let manager = UserTokenManager(provider: { nil })
        manager.onProviderFailure = { _ in failures.update { $0 += 1 } }
        XCTAssertNil(get(manager))
        XCTAssertEqual(failures.value, 0)
    }

    func testProviderTimeout() {
        let failures = Locked<[Error]>([])
        let manager = UserTokenManager(timeout: 0.3)
        manager.setCallbackProvider { _ in /* never answers */ }
        manager.onProviderFailure = { error in failures.update { $0.append(error) } }
        XCTAssertNil(get(manager))
        XCTAssertEqual(failures.value.count, 1)
        XCTAssertTrue(failures.value.first is UserTokenError)
    }

    /// A provider that answers on the main queue (as a wrapper plugin does)
    /// is called off the main thread and does not deadlock a main-thread caller.
    func testProviderMayHopToMainQueue() {
        let calledOnMain = Locked<Bool?>(nil)
        let manager = UserTokenManager()
        manager.setCallbackProvider { completion in
            calledOnMain.value = Thread.isMainThread
            DispatchQueue.main.async { completion(.success("from-main")) }
        }
        XCTAssertTrue(Thread.isMainThread)
        XCTAssertEqual(get(manager), "from-main")
        XCTAssertEqual(calledOnMain.value, false)
    }

    func testStaleTokenIsUsedOnlyWhileUnexpiredWhenProviderFails() {
        let clock = Locked(Date(timeIntervalSince1970: base))
        let manager = UserTokenManager(now: { clock.value })
        let token = makeToken(exp: base + 100)
        manager.set(token)
        manager.setProvider { throw ProviderError() }
        manager.set(token)

        clock.value = Date(timeIntervalSince1970: base + 70)  // inside the margin, not expired
        XCTAssertEqual(get(manager), token)
        clock.value = Date(timeIntervalSince1970: base + 101)  // expired
        XCTAssertNil(get(manager))
        XCTAssertNil(manager.current())
    }

    func testSetUserTokenWithoutProvider() {
        let clock = Locked(Date(timeIntervalSince1970: base))
        let manager = UserTokenManager(now: { clock.value })
        XCTAssertNil(get(manager))

        let token = makeToken(exp: base + 100)
        manager.set(token)
        XCTAssertEqual(get(manager), token)
        clock.value = Date(timeIntervalSince1970: base + 200)
        XCTAssertNil(get(manager), "an expired token is not sent")

        manager.set(token)
        manager.set(nil)
        XCTAssertNil(manager.current())
    }

    func testPrepareDropsTokenOfAnotherUser() {
        let manager = UserTokenManager()
        manager.set(makeToken(sub: "alice"))
        manager.prepare(forUserId: "alice")
        XCTAssertNotNil(manager.current())
        manager.prepare(forUserId: "bob")
        XCTAssertNil(manager.current())
    }

    func testPersistsLastTokenAndSkipsExpiredOne() {
        let store = MemoryTokenStore()
        let clock = Locked(Date(timeIntervalSince1970: base))
        let token = makeToken(exp: base + 100)

        UserTokenManager(store: store, now: { clock.value }).set(token)
        XCTAssertEqual(store.token, token)

        // A new process with no provider still has it while it is unexpired.
        XCTAssertEqual(UserTokenManager(store: store, now: { clock.value }).current(), token)

        clock.value = Date(timeIntervalSince1970: base + 500)
        XCTAssertNil(UserTokenManager(store: store, now: { clock.value }).current())
        XCTAssertNil(store.token)

        let manager = UserTokenManager(store: store)
        manager.set("opaque")
        XCTAssertEqual(store.token, "opaque")
        manager.clear()
        XCTAssertNil(store.token)
    }

    // MARK: Storage

    private func withLegacyDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "co.rivium.push.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }

    func testMovesTokenFromUserDefaultsToTheStore() {
        withLegacyDefaults { defaults in
            let key = UserTokenManager.legacyDefaultsKey
            let store = MemoryTokenStore()
            let clock = Locked(Date(timeIntervalSince1970: base))
            let token = makeToken(exp: base + 100)
            defaults.set(token, forKey: key)

            let manager = UserTokenManager(store: store, legacyDefaults: defaults, now: { clock.value })
            XCTAssertEqual(manager.current(), token)
            XCTAssertEqual(store.token, token)
            XCTAssertNil(defaults.string(forKey: key))

            // The next launch reads it from the store alone.
            XCTAssertEqual(UserTokenManager(store: store, legacyDefaults: defaults, now: { clock.value }).current(), token)
            XCTAssertEqual(store.writes, 1)
        }
    }

    func testFreshInstallDropsTokenLeftByPreviousInstall() {
        withLegacyDefaults { defaults in
            let store = MemoryTokenStore()
            store.token = "from-previous-install"

            XCTAssertNil(UserTokenManager(store: store, legacyDefaults: defaults).current())
            XCTAssertNil(store.token)

            // Later launches of the same install keep what was saved.
            store.token = "saved-by-this-install"
            XCTAssertEqual(UserTokenManager(store: store, legacyDefaults: defaults).current(), "saved-by-this-install")
        }
    }

    func testStoreWinsOverLeftoverUserDefaultsValue() {
        withLegacyDefaults { defaults in
            let key = UserTokenManager.legacyDefaultsKey
            let store = MemoryTokenStore()
            store.token = "from-store"
            defaults.set("left-behind", forKey: key)

            XCTAssertEqual(UserTokenManager(store: store, legacyDefaults: defaults).current(), "from-store")
            XCTAssertEqual(store.token, "from-store")
            XCTAssertNil(defaults.string(forKey: key))
        }
    }

    func testExpiredUserDefaultsTokenIsDroppedNotMoved() {
        withLegacyDefaults { defaults in
            let key = UserTokenManager.legacyDefaultsKey
            let store = MemoryTokenStore()
            defaults.set(makeToken(exp: base - 1), forKey: key)

            let manager = UserTokenManager(
                store: store, legacyDefaults: defaults, now: { Date(timeIntervalSince1970: self.base) }
            )
            XCTAssertNil(manager.current())
            XCTAssertNil(store.token)
            XCTAssertEqual(store.writes, 0)
            XCTAssertNil(defaults.string(forKey: key))
        }
    }

    func testClearRemovesStoreAndUserDefaults() {
        withLegacyDefaults { defaults in
            let key = UserTokenManager.legacyDefaultsKey
            let store = MemoryTokenStore()
            store.failWrites = true  // the move fails, so both places hold a token
            defaults.set("legacy", forKey: key)
            let manager = UserTokenManager(store: store, legacyDefaults: defaults)
            XCTAssertEqual(manager.current(), "legacy")
            XCTAssertEqual(defaults.string(forKey: key), "legacy")
            store.token = "stale"

            manager.clear()
            XCTAssertNil(manager.current())
            XCTAssertNil(store.token)
            XCTAssertNil(defaults.string(forKey: key))
        }
    }

    func testSettingATokenNeverWritesUserDefaults() {
        withLegacyDefaults { defaults in
            let key = UserTokenManager.legacyDefaultsKey
            let store = MemoryTokenStore()
            defaults.set("legacy", forKey: key)
            let manager = UserTokenManager(store: store, legacyDefaults: defaults)

            manager.set("new")
            XCTAssertEqual(store.token, "new")
            XCTAssertNil(defaults.string(forKey: key))

            store.failWrites = true
            manager.set("newer")
            XCTAssertNil(defaults.string(forKey: key), "no fallback to UserDefaults")
        }
    }

    func testFailedReadMeansNoSavedToken() {
        let store = MemoryTokenStore()
        store.token = "saved"
        store.failReads = true

        let manager = UserTokenManager(store: store)
        XCTAssertNil(manager.current())
        XCTAssertNil(get(manager))

        // The SDK keeps working from memory.
        manager.set("fresh")
        XCTAssertEqual(get(manager), "fresh")
    }

    func testFailedWriteKeepsTokenInMemoryOnly() {
        let store = MemoryTokenStore()
        store.token = "older"
        store.failWrites = true

        let manager = UserTokenManager(store: store)
        manager.set("fresh")
        XCTAssertEqual(manager.current(), "fresh")
        XCTAssertEqual(get(manager), "fresh")
        XCTAssertNil(store.token, "an older saved token is not left behind")
        XCTAssertNil(UserTokenManager(store: store).current())
    }

    func testStoreThatFailsEverythingIsTolerated() {
        withLegacyDefaults { defaults in
            let key = UserTokenManager.legacyDefaultsKey
            let store = MemoryTokenStore()
            store.failReads = true
            store.failWrites = true
            store.failRemoves = true
            defaults.set("legacy", forKey: key)

            let manager = UserTokenManager(provider: { "from-provider" }, store: store, legacyDefaults: defaults)
            // Not moved, so it is still there for the next launch to move.
            XCTAssertEqual(manager.current(), "legacy")
            XCTAssertEqual(defaults.string(forKey: key), "legacy")

            XCTAssertEqual(refresh(manager), "from-provider")
            manager.prepare(forUserId: "someone")
            manager.clear()
            XCTAssertNil(manager.current())
            XCTAssertNil(defaults.string(forKey: key))
        }
    }

    func testSavedTokenOfAnotherUserIsDropped() {
        let store = MemoryTokenStore()
        store.token = makeToken(sub: "alice")

        let manager = UserTokenManager(store: store)
        manager.prepare(forUserId: "bob")
        XCTAssertNil(manager.current())
        XCTAssertNil(store.token)
    }

    /// Runs against the real Keychain. A test bundle without a host app may
    /// not be allowed to use it; the store must then report failure, not crash.
    func testKeychainStoreRoundTripOrFailsQuietly() {
        let store = KeychainUserTokenStore(
            service: "co.rivium.push.tests.\(UUID().uuidString)", account: "userToken"
        )
        defer { store.remove() }

        guard store.write("first") else {
            XCTAssertNil(store.read())
            store.remove()
            return
        }
        XCTAssertEqual(store.read(), "first")
        XCTAssertTrue(store.write("second"))
        XCTAssertEqual(store.read(), "second")
        XCTAssertTrue(store.remove())
        XCTAssertNil(store.read())
        XCTAssertTrue(store.remove(), "removing nothing is not a failure")
    }

    /// A provider written for another Rivium SDK (non-optional result) fits as is.
    func testAcceptsProviderReturningNonOptionalString() {
        let shared: () async throws -> String = { "one-token" }
        let config = RiviumPushConfig(apiKey: "k", tokenProvider: shared)
        XCTAssertNotNil(config.tokenProvider)
        XCTAssertNotNil(RiviumPushConfig.builder(apiKey: "k").tokenProvider(shared).build().tokenProvider)
        XCTAssertNil(RiviumPushConfig(apiKey: "k").tokenProvider)
        XCTAssertEqual(get(UserTokenManager(provider: shared)), "one-token")
    }
}

final class UserTokenHttpTests: XCTestCase {
    private let ok: [String: Any] = ["success": true]

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func makeClient(
        provider: RiviumPushTokenProvider? = nil,
        events: Locked<[RiviumPushAuthErrorEvent]>? = nil
    ) -> ApiClient {
        let config = RiviumPushConfig(apiKey: "rv_test_key", tokenProvider: provider)
        let client = ApiClient(
            config: config,
            session: RetryingURLSession(protocolClasses: [MockURLProtocol.self])
        )
        client.onAuthError = { event in events?.update { $0.append(event) } }
        return client
    }

    private func authError(_ status: Int, code: String? = nil, message: String = "nope") -> (HTTPURLResponse, Data?) {
        var body: [String: Any] = ["statusCode": status, "error": "Unauthorized", "message": message]
        if let code = code { body["code"] = code }
        return MockURLProtocol.mockResponse(statusCode: status, json: body)
    }

    /// Runs one request to completion and lets queued main-queue callbacks land.
    @discardableResult
    private func subscribe(_ client: ApiClient) -> Result<ApiClient.GenericResponse, Error>? {
        let done = expectation(description: "request")
        var outcome: Result<ApiClient.GenericResponse, Error>?
        client.subscribeTopic(deviceId: "d1", topic: "news") { result in
            outcome = result
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        return outcome
    }

    private func isSuccess<T>(_ result: Result<T, Error>?) -> Bool {
        if case .success = result { return true }
        return false
    }

    private func tokens() -> [String?] {
        return MockURLProtocol.recordedRequests.map { $0.value(forHTTPHeaderField: "x-user-token") }
    }

    func testNoProviderRequestsAreUnchanged() {
        MockURLProtocol.requestHandler = { _ in MockURLProtocol.mockResponse(json: self.ok) }
        let events = Locked<[RiviumPushAuthErrorEvent]>([])
        let client = makeClient(events: events)

        XCTAssertTrue(isSuccess(subscribe(client)))

        XCTAssertEqual(MockURLProtocol.recordedRequests.count, 1)
        let request = MockURLProtocol.recordedRequests[0]
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/topics/subscribe")
        let sent = Set((request.allHTTPHeaderFields ?? [:]).keys.map { $0.lowercased() })
        XCTAssertEqual(
            sent.intersection(["content-type", "x-api-key", "x-rivium-sdk", "x-user-token"]),
            ["content-type", "x-api-key", "x-rivium-sdk"]
        )
        XCTAssertNil(request.value(forHTTPHeaderField: "x-user-token"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "rv_test_key")
        XCTAssertTrue(events.value.isEmpty)
    }

    func testHeaderSentWhenProviderGivesToken() {
        MockURLProtocol.requestHandler = { _ in MockURLProtocol.mockResponse(json: self.ok) }
        let calls = Locked(0)
        let client = makeClient(provider: {
            calls.update { $0 += 1 }
            return "tok-A"
        })

        XCTAssertTrue(isSuccess(subscribe(client)))
        XCTAssertTrue(isSuccess(subscribe(client)))

        XCTAssertEqual(tokens(), ["tok-A", "tok-A"])
        XCTAssertEqual(calls.value, 1)
    }

    func testSignedOutSendsNoHeader() {
        MockURLProtocol.requestHandler = { _ in MockURLProtocol.mockResponse(json: self.ok) }
        let events = Locked<[RiviumPushAuthErrorEvent]>([])
        let client = makeClient(provider: { nil }, events: events)

        XCTAssertTrue(isSuccess(subscribe(client)))
        XCTAssertEqual(tokens(), [nil])
        XCTAssertTrue(events.value.isEmpty)
    }

    func testRetriesOnceOnTokenExpired() {
        let served = Locked(0)
        MockURLProtocol.requestHandler = { _ in
            served.update { $0 += 1 }
            return served.value == 1
                ? self.authError(401, code: "token_expired")
                : MockURLProtocol.mockResponse(json: self.ok)
        }
        let calls = Locked(0)
        let events = Locked<[RiviumPushAuthErrorEvent]>([])
        let client = makeClient(provider: {
            calls.update { $0 += 1 }
            return "tok-\(calls.value)"
        }, events: events)

        XCTAssertTrue(isSuccess(subscribe(client)))
        XCTAssertEqual(tokens(), ["tok-1", "tok-2"])
        XCTAssertEqual(calls.value, 2)
        XCTAssertTrue(events.value.isEmpty)
    }

    func testNeverLoopsWhenTokenStaysExpired() {
        MockURLProtocol.requestHandler = { _ in self.authError(401, code: "token_expired") }
        let calls = Locked(0)
        let events = Locked<[RiviumPushAuthErrorEvent]>([])
        let client = makeClient(provider: {
            calls.update { $0 += 1 }
            return "tok-\(calls.value)"
        }, events: events)

        let result = subscribe(client)
        XCTAssertFalse(isSuccess(result))
        if case .failure(let error)? = result, let pushError = error as? RiviumPushError {
            XCTAssertEqual(pushError.errorCode, .serverError)
        } else {
            XCTFail("expected the request's usual server error")
        }
        XCTAssertEqual(MockURLProtocol.recordedRequests.count, 2)
        XCTAssertEqual(events.value.map { $0.code }, ["token_expired"])
    }

    func testNoRetryOnTokenInvalid() {
        MockURLProtocol.requestHandler = { _ in self.authError(401, code: "token_invalid", message: "bad token") }
        let events = Locked<[RiviumPushAuthErrorEvent]>([])
        let client = makeClient(provider: { "tok-A" }, events: events)

        XCTAssertFalse(isSuccess(subscribe(client)))
        XCTAssertEqual(MockURLProtocol.recordedRequests.count, 1)
        XCTAssertEqual(events.value.map { $0.code }, ["token_invalid"])
        XCTAssertEqual(events.value.first?.message, "bad token")
    }

    func testTokenRequiredIsReportedWithoutProvider() {
        MockURLProtocol.requestHandler = { _ in self.authError(401, code: "token_required") }
        let events = Locked<[RiviumPushAuthErrorEvent]>([])
        let client = makeClient(events: events)

        XCTAssertFalse(isSuccess(subscribe(client)))
        XCTAssertEqual(MockURLProtocol.recordedRequests.count, 1)
        XCTAssertEqual(events.value.map { $0.code }, ["token_required"])
    }

    func testPlain401IsNotAnAuthError() {
        MockURLProtocol.requestHandler = { _ in self.authError(401) }
        let events = Locked<[RiviumPushAuthErrorEvent]>([])
        let client = makeClient(provider: { "tok-A" }, events: events)

        XCTAssertFalse(isSuccess(subscribe(client)))
        XCTAssertEqual(MockURLProtocol.recordedRequests.count, 1)
        XCTAssertTrue(events.value.isEmpty)
    }

    func testUserIdMismatchIsReported() {
        MockURLProtocol.requestHandler = { _ in
            self.authError(403, message: "userId does not match the user token")
        }
        let events = Locked<[RiviumPushAuthErrorEvent]>([])
        let client = makeClient(provider: { "tok-A" }, events: events)

        XCTAssertFalse(isSuccess(subscribe(client)))
        XCTAssertEqual(MockURLProtocol.recordedRequests.count, 1)
        XCTAssertEqual(events.value.map { $0.code }, ["token_mismatch"])
    }

    func testProviderFailureStillSendsRequestWithoutHeader() {
        MockURLProtocol.requestHandler = { _ in MockURLProtocol.mockResponse(json: self.ok) }
        let events = Locked<[RiviumPushAuthErrorEvent]>([])
        let client = makeClient(provider: { throw ProviderError() }, events: events)

        XCTAssertTrue(isSuccess(subscribe(client)))
        XCTAssertEqual(tokens(), [nil])
        XCTAssertEqual(events.value.map { $0.code }, ["token_provider_failed"])
        XCTAssertTrue(events.value.first?.error is ProviderError)
    }

    func testSetUserTokenIsSentWithoutProvider() {
        MockURLProtocol.requestHandler = { _ in MockURLProtocol.mockResponse(json: self.ok) }
        let client = makeClient()
        client.userTokens.set("tok-manual")

        XCTAssertTrue(isSuccess(subscribe(client)))
        XCTAssertEqual(tokens(), ["tok-manual"])
    }

    func testClearUserIdSendsTokenThenForgetsIt() {
        MockURLProtocol.requestHandler = { _ in MockURLProtocol.mockResponse(json: self.ok) }
        let client = makeClient()
        client.userTokens.set("tok-manual")

        let done = expectation(description: "clear")
        client.clearUserId(deviceId: "d1") { _ in done.fulfill() }
        wait(for: [done], timeout: 10)

        XCTAssertEqual(tokens(), ["tok-manual"])
        XCTAssertEqual(MockURLProtocol.recordedRequests.first?.httpMethod, "DELETE")
        XCTAssertNil(client.userTokens.current())

        subscribe(client)
        XCTAssertEqual(tokens(), ["tok-manual", nil])
    }

    func testTokenRefreshRouteCarriesTheHeader() {
        MockURLProtocol.requestHandler = { _ in
            MockURLProtocol.mockResponse(json: ["deviceId": "d1", "token": "mqtt-jwt"])
        }
        let client = makeClient(provider: { "tok-A" })

        let done = expectation(description: "refresh")
        client.refreshPNToken(deviceId: "d1") { _ in done.fulfill() }
        wait(for: [done], timeout: 10)

        XCTAssertEqual(tokens(), ["tok-A"])
        XCTAssertEqual(MockURLProtocol.recordedRequests.first?.url?.path, "/devices/d1/mqtt-token/refresh")
    }
}
