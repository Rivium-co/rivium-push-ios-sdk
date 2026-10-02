import Foundation

/// Returns the Rivium user token for the signed-in user, issued by your server,
/// or nil when no user is signed in.
///
/// It is the same token the other Rivium SDKs take, so one function can serve
/// all of them. Never put the server secret in the app.
public typealias RiviumPushTokenProvider = () async throws -> String?

/// Completion-handler form of ``RiviumPushTokenProvider``, for callers that
/// cannot use async/await. Call `completion` exactly once, from any thread.
public typealias RiviumPushTokenCallbackProvider =
    (_ completion: @escaping (Result<String?, Error>) -> Void) -> Void

/// The server refused the user's identity, or the app's token provider failed.
/// Typically: send the user to login.
///
/// `code` is the server's reason (`token_invalid`, `token_required`,
/// `token_expired` after a failed refresh), `token_mismatch` when the user id
/// given to the SDK is not the token's user, or `token_provider_failed`.
public struct RiviumPushAuthErrorEvent {
    public let code: String
    public let message: String
    public let error: Error?

    public init(code: String, message: String, error: Error? = nil) {
        self.code = code
        self.message = message
        self.error = error
    }
}

internal enum UserTokenError: Error {
    /// The provider did not answer in time.
    case providerTimedOut
}

/// The two claims the SDK reads from a user token. The token is otherwise
/// opaque: the signature is checked by the server, not on the device.
internal struct UserTokenClaims {
    let expiresAt: Date?
    let subject: String?

    /// Never throws: anything unreadable yields empty claims.
    static func read(_ token: String) -> UserTokenClaims {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return UserTokenClaims(expiresAt: nil, subject: nil) }

        var base64 = String(parts[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 = base64.replacingOccurrences(of: "=", with: "")
        while base64.count % 4 != 0 { base64 += "=" }

        guard let data = Data(base64Encoded: base64),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return UserTokenClaims(expiresAt: nil, subject: nil) }

        let exp = (json["exp"] as? NSNumber)?.doubleValue
        return UserTokenClaims(
            expiresAt: exp.map { Date(timeIntervalSince1970: $0) },
            subject: json["sub"] as? String
        )
    }
}

/// Holds the current user token and refreshes it through the app's provider.
///
/// - Reuses the cached token until shortly before it expires.
/// - Concurrent callers share one in-flight provider call.
/// - Never blocks a thread: the provider runs off the main thread and may hop
///   to the main queue freely. A provider that does not answer in time counts
///   as failed.
/// - Keeps the last token on disk so work that runs while no provider can
///   answer still sends it while it is unexpired.
internal final class UserTokenManager {
    /// Refresh this long before `exp`, to absorb clock skew and request time.
    static let refreshMargin: TimeInterval = 60
    /// How long the provider may take before the request goes out without a token.
    static let providerTimeout: TimeInterval = 10
    static let storageKey = "co.rivium.push.userToken"

    private let lock = NSLock()
    private let defaults: UserDefaults?
    private let timeout: TimeInterval
    private let now: () -> Date

    private var provider: RiviumPushTokenCallbackProvider?
    private var token: String?
    private var claims = UserTokenClaims(expiresAt: nil, subject: nil)

    private var fetching = false
    private var fetchId = 0
    /// Bumped whenever the token or provider is replaced from outside, so an
    /// answer to an older provider call is not cached over it.
    private var epoch = 0
    private var waiters: [(String?) -> Void] = []

    /// The provider threw or timed out. Not called for a plain nil (signed out).
    var onProviderFailure: ((Error) -> Void)?

    init(
        provider: RiviumPushTokenProvider? = nil,
        defaults: UserDefaults? = nil,
        timeout: TimeInterval = UserTokenManager.providerTimeout,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.timeout = timeout
        self.now = now
        self.provider = provider.map(UserTokenManager.adapt)

        // An expired stored token is never sent.
        if let stored = defaults?.string(forKey: UserTokenManager.storageKey), !stored.isEmpty {
            let storedClaims = UserTokenClaims.read(stored)
            if let exp = storedClaims.expiresAt, now() >= exp {
                defaults?.removeObject(forKey: UserTokenManager.storageKey)
            } else {
                token = stored
                claims = storedClaims
            }
        }
    }

    // MARK: - Provider

    var hasProvider: Bool {
        lock.lock(); defer { lock.unlock() }
        return provider != nil
    }

    func setProvider(_ provider: RiviumPushTokenProvider?) {
        setCallbackProvider(provider.map(UserTokenManager.adapt))
    }

    func setCallbackProvider(_ provider: RiviumPushTokenCallbackProvider?) {
        lock.lock(); defer { lock.unlock() }
        self.provider = provider
        epoch += 1
    }

    private static func adapt(_ provider: @escaping RiviumPushTokenProvider) -> RiviumPushTokenCallbackProvider {
        return { completion in
            Task.detached {
                do {
                    completion(.success(try await provider()))
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - Token

    /// The token to send, or nil to send none. Completes at once when a cached
    /// token is usable or there is no provider.
    func get(_ completion: @escaping (String?) -> Void) {
        lock.lock()
        if let token = token, isFreshLocked() {
            lock.unlock()
            completion(token)
            return
        }
        if provider == nil {
            let usable = unexpiredLocked()
            lock.unlock()
            completion(usable)
            return
        }
        lock.unlock()
        refresh(completion)
    }

    /// Asks the provider for a new token even if the cached one looks valid.
    /// Joins a call already in flight. Without a provider there is nothing to
    /// ask: completes with nil.
    func refresh(_ completion: @escaping (String?) -> Void) {
        lock.lock()
        guard let provider = provider else {
            lock.unlock()
            completion(nil)
            return
        }
        waiters.append(completion)
        if fetching {
            lock.unlock()
            return
        }
        fetching = true
        fetchId += 1
        let id = fetchId
        let startedIn = epoch
        lock.unlock()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            provider { result in
                self?.finish(id: id, epoch: startedIn, result: result)
            }
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.finish(id: id, epoch: startedIn, result: .failure(UserTokenError.providerTimedOut))
        }
    }

    /// The cached token if it has not expired. Never calls the provider.
    func current() -> String? {
        lock.lock(); defer { lock.unlock() }
        return unexpiredLocked()
    }

    /// Replace the token (nil forgets it).
    func set(_ newToken: String?) {
        lock.lock(); defer { lock.unlock() }
        epoch += 1
        if let newToken = newToken, !newToken.isEmpty {
            storeLocked(newToken)
        } else {
            forgetLocked()
        }
    }

    /// Forgets the cached token.
    func clear() {
        set(nil)
    }

    /// Forgets the cached token only if it is still `used`, so a token set in
    /// the meantime survives.
    func clear(ifTokenIs used: String) {
        lock.lock(); defer { lock.unlock() }
        guard token == used else { return }
        epoch += 1
        forgetLocked()
    }

    /// Drops a cached token that belongs to another user.
    func prepare(forUserId userId: String) {
        lock.lock(); defer { lock.unlock() }
        guard token != nil, let subject = claims.subject, subject != userId else { return }
        epoch += 1
        forgetLocked()
    }

    // MARK: - Private

    private func finish(id: Int, epoch startedIn: Int, result: Result<String?, Error>) {
        lock.lock()
        let fetched: String? = {
            if case .success(let value) = result, let value = value, !value.isEmpty { return value }
            return nil
        }()

        guard fetching, id == fetchId else {
            // Answered after the timeout: keep a good token for the next request.
            if let fetched = fetched, id == fetchId, startedIn == epoch { storeLocked(fetched) }
            lock.unlock()
            return
        }

        fetching = false
        let pending = waiters
        waiters = []
        var failure: Error?
        var outcome: String?

        switch result {
        case .success:
            if startedIn == epoch {
                if let fetched = fetched { storeLocked(fetched) } else { forgetLocked() }
            }
            outcome = fetched
        case .failure(let error):
            failure = error
            // A token that has not expired yet is still better than none.
            outcome = unexpiredLocked()
        }
        lock.unlock()

        if let failure = failure { onProviderFailure?(failure) }
        pending.forEach { $0(outcome) }
    }

    private func isFreshLocked() -> Bool {
        guard let exp = claims.expiresAt else { return true }  // no exp claim: assume usable
        return now() < exp.addingTimeInterval(-UserTokenManager.refreshMargin)
    }

    private func unexpiredLocked() -> String? {
        guard let token = token else { return nil }
        if let exp = claims.expiresAt, now() >= exp { return nil }
        return token
    }

    private func storeLocked(_ newToken: String) {
        token = newToken
        claims = UserTokenClaims.read(newToken)
        defaults?.set(newToken, forKey: UserTokenManager.storageKey)
    }

    private func forgetLocked() {
        token = nil
        claims = UserTokenClaims(expiresAt: nil, subject: nil)
        defaults?.removeObject(forKey: UserTokenManager.storageKey)
    }
}
