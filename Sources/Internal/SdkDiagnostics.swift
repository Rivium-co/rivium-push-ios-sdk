import Foundation

/// SDK self-reports. The SDK counts
/// its own errors by the public `RiviumPushErrorCode` number every Rivium Push
/// SDK shares, and sends the counts with its next ordinary API request in one
/// header:
///
///     X-Rivium-SDK-Report: 1000=3 1400=1
///
/// Counts only — never a message, stack trace, key, user or device detail. A
/// count is cleared only after the server answered 2xx, so nothing is lost while
/// offline and nothing is counted twice. Switched off with
/// `RiviumPushConfig.sendDiagnostics = false`: nothing is counted, kept or sent.
/// (Crashes are not counted on iOS: an SDK cannot safely install signal
/// handlers next to the app's own crash reporter.)
internal final class SdkDiagnostics {
    static let shared = SdkDiagnostics(defaults: .standard)

    static let header = "X-Rivium-SDK-Report"
    /// Most codes per report and highest count per code (the server accepts no more).
    static let maxCodes = 16
    static let maxCount = 9999

    private static let key = "co.rivium.push.diagnostics"
    private let defaults: UserDefaults
    private let lock = NSLock()
    private var enabled = true

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// From `RiviumPush.initialize`; false also forgets what was kept.
    func setEnabled(_ on: Bool) {
        lock.lock(); defer { lock.unlock() }
        enabled = on
        if !on { defaults.removeObject(forKey: Self.key) }
    }

    func count(_ code: RiviumPushErrorCode) { count(code.rawValue) }

    /// Adds one. A 17th distinct code is dropped.
    func count(_ code: Int) {
        lock.lock(); defer { lock.unlock() }
        guard enabled else { return }
        var counts = stored()
        let key = String(code)
        if counts[key] == nil && counts.count >= Self.maxCodes { return }
        counts[key] = min(Self.maxCount, (counts[key] ?? 0) + 1)
        defaults.set(counts, forKey: Self.key)
    }

    /// What would be sent now: code → count.
    func pending() -> [Int: Int] {
        lock.lock(); defer { lock.unlock() }
        guard enabled else { return [:] }
        var out: [Int: Int] = [:]
        for (k, v) in stored() { if let code = Int(k), v > 0 { out[code] = v } }
        return out
    }

    /// `1000=3 1400=1`, or nil when there is nothing to send. Codes in ascending order.
    static func headerValue(_ snapshot: [Int: Int]) -> String? {
        guard !snapshot.isEmpty else { return nil }
        return snapshot.keys.sorted().prefix(maxCodes)
            .map { "\($0)=\(min(maxCount, max(1, snapshot[$0] ?? 1)))" }
            .joined(separator: " ")
    }

    /// The server took `snapshot`: subtract it (counts added meanwhile stay for the next request).
    func acknowledge(_ snapshot: [Int: Int]) {
        lock.lock(); defer { lock.unlock() }
        var counts = stored()
        for (code, sent) in snapshot {
            let key = String(code)
            let left = (counts[key] ?? 0) - sent
            counts[key] = left > 0 ? left : nil
        }
        defaults.set(counts, forKey: Self.key)
    }

    /// Adds the report to `request`; returns what it carries (empty = nothing added).
    func attach(to request: inout URLRequest) -> [Int: Int] {
        let snapshot = pending()
        guard let value = Self.headerValue(snapshot) else { return [:] }
        request.setValue(value, forHTTPHeaderField: Self.header)
        return snapshot
    }

    private func stored() -> [String: Int] {
        return defaults.dictionary(forKey: Self.key) as? [String: Int] ?? [:]
    }
}
