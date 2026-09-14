import Foundation

// Code shared by the app SDK (RiviumPushSDK) and the Notification Service
// Extension pod (RiviumPushSDKExtension). Must stay extension-safe:
// Foundation only, no UIApplication.

// MARK: - SDK identity

/// Identity this SDK reports to the backend (`sdkName` / `sdkVersion` in the
/// register body and the `X-Rivium-SDK: name/version` header).
internal enum RiviumPushSDKInfo {
    /// Native iOS SDK name.
    static let name = "ios"

    /// Single source of truth for the SDK version. Must match both podspecs;
    /// `SdkIdentityTests` fails when they drift.
    static let version = "0.1.12"

    /// Header carrying the SDK identity on every request.
    static let headerName = "X-Rivium-SDK"

    /// App Group key the app mirrors its reported identity under, so the
    /// extension reports the same identity (including a wrapper's).
    static let sharedIdentityKey = "co.rivium.push.sharedSdkIdentity"

    private static let maxLength = 32
    private static let allowed = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._+-")

    /// Strip characters the backend rejects and cap the length (≤32,
    /// `[A-Za-z0-9._+-]`). Returns nil if nothing usable is left.
    static func sanitize(_ value: String?) -> String? {
        guard let value = value else { return nil }
        let scalars = value.unicodeScalars.filter { allowed.contains($0) }
        let cleaned = String(String.UnicodeScalarView(scalars).prefix(maxLength))
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Resolve the reported identity. A wrapper identity replaces the native
    /// one only when both its name and version are usable.
    static func identity(wrapperName: String?, wrapperVersion: String?) -> (name: String, version: String) {
        if let n = sanitize(wrapperName), let v = sanitize(wrapperVersion) {
            return (n, v)
        }
        return (name, version)
    }

    static func headerValue(name: String, version: String) -> String {
        return "\(name)/\(version)"
    }
}

// MARK: - Delivery receipt dedupe

/// Bounded, persisted set of message ids whose delivery has been (or is being)
/// reported. Stored in the App Group when one is configured, so the app and
/// the Notification Service Extension do not both report the same message.
/// The server is idempotent, so a rare cross-process race only costs a
/// duplicate request, never a double count.
internal final class DeliveryReceiptStore {
    static let storageKey = "co.rivium.push.deliveredMessageIds"
    static let defaultCapacity = 200

    private let defaults: UserDefaults
    private let capacity: Int
    private let lock = NSLock()

    init(defaults: UserDefaults, capacity: Int = DeliveryReceiptStore.defaultCapacity) {
        self.defaults = defaults
        self.capacity = max(1, capacity)
    }

    /// Store in the App Group if available, otherwise the app's defaults.
    convenience init(appGroup: String?) {
        let shared = appGroup.flatMap { UserDefaults(suiteName: $0) }
        self.init(defaults: shared ?? .standard)
    }

    /// Atomically mark `messageId` as reported. Returns true if this caller
    /// should send the receipt, false if it was already claimed.
    func claim(_ messageId: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        var ids = defaults.stringArray(forKey: Self.storageKey) ?? []
        if ids.contains(messageId) { return false }
        ids.append(messageId)
        if ids.count > capacity { ids.removeFirst(ids.count - capacity) }
        defaults.set(ids, forKey: Self.storageKey)
        return true
    }

    /// Release a claim after the receipt could not be sent, so another path
    /// (e.g. the app after the extension failed) may try again.
    func release(_ messageId: String) {
        lock.lock(); defer { lock.unlock() }
        var ids = defaults.stringArray(forKey: Self.storageKey) ?? []
        ids.removeAll { $0 == messageId }
        defaults.set(ids, forKey: Self.storageKey)
    }

    func contains(_ messageId: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return (defaults.stringArray(forKey: Self.storageKey) ?? []).contains(messageId)
    }
}

// MARK: - Delivery receipt sender

/// POST /receipts/delivered with a small bounded retry for transient failures.
internal enum DeliveryReceiptSender {
    /// Delay before retry `attempt` (1-based): 1s, 2s, 4s… capped at 8s.
    static func backoff(forRetry attempt: Int) -> TimeInterval {
        return min(8, pow(2, Double(max(0, attempt - 1))))
    }

    /// Network errors and 408/429/5xx are worth retrying; other 4xx are not.
    static func isTransient(statusCode: Int?, error: Error?) -> Bool {
        if let error = error as NSError? {
            return error.domain == NSURLErrorDomain && error.code != NSURLErrorCancelled
        }
        guard let code = statusCode else { return true }
        return code == 408 || code == 429 || (500...599).contains(code)
    }

    static func send(
        messageId: String,
        deviceId: String,
        apiKey: String,
        serverUrl: String,
        sdkHeader: String,
        maxAttempts: Int,
        timeout: TimeInterval,
        session: URLSession = .shared,
        completion: @escaping (Bool) -> Void
    ) {
        guard let url = URL(string: "\(serverUrl)/receipts/delivered"),
              let body = try? JSONSerialization.data(withJSONObject: ["messageId": messageId, "deviceId": deviceId])
        else {
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(sdkHeader, forHTTPHeaderField: RiviumPushSDKInfo.headerName)
        request.timeoutInterval = timeout
        request.httpBody = body

        func attempt(_ n: Int) {
            session.dataTask(with: request) { _, response, error in
                let status = (response as? HTTPURLResponse)?.statusCode
                if error == nil, let status = status, (200...299).contains(status) {
                    completion(true)
                    return
                }
                if n < maxAttempts && isTransient(statusCode: status, error: error) {
                    DispatchQueue.global().asyncAfter(deadline: .now() + backoff(forRetry: n)) {
                        attempt(n + 1)
                    }
                    return
                }
                completion(false)
            }.resume()
        }
        attempt(1)
    }
}
