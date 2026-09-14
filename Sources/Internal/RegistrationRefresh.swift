import Foundation

/// What a registration looked like the last time it succeeded. A change in
/// any field means the server's device record is stale.
internal struct RegistrationFingerprint: Codable, Equatable {
    var appVersion: String?
    var appBuild: String?
    /// `name/version` as reported to the backend.
    var sdkIdentity: String
    var apnsToken: String?
    var voipToken: String?
    var userId: String?
}

internal enum RegistrationRefresh {
    /// OneSignal refreshes the player record once per session after 24h;
    /// we use the same cadence.
    static let refreshInterval: TimeInterval = 24 * 60 * 60

    enum Reason: String, Equatable {
        case neverRecorded
        case intervalElapsed
        case appVersionChanged
        case sdkChanged
        case tokenChanged
        case userChanged
    }

    /// Decide whether launch should re-send the registration.
    ///
    /// - Parameters:
    ///   - hasRegistered: the install registered successfully at least once.
    ///     Never auto-register a fresh install; that is the app's explicit call.
    ///   - lastSuccess: time of the last successful registration.
    ///   - stored: fingerprint saved with that registration.
    ///   - current: fingerprint of the registration that would be sent now.
    ///     A nil token means "not known yet" and is not treated as a change.
    /// - Returns: why a refresh is needed, or nil to skip.
    static func reason(
        hasRegistered: Bool,
        lastSuccess: Date?,
        now: Date,
        stored: RegistrationFingerprint?,
        current: RegistrationFingerprint,
        interval: TimeInterval = refreshInterval
    ) -> Reason? {
        guard hasRegistered else { return nil }
        guard let stored = stored, let lastSuccess = lastSuccess else { return .neverRecorded }

        if stored.appVersion != current.appVersion || stored.appBuild != current.appBuild {
            return .appVersionChanged
        }
        if stored.sdkIdentity != current.sdkIdentity { return .sdkChanged }
        if let token = current.apnsToken, token != stored.apnsToken { return .tokenChanged }
        if let token = current.voipToken, token != stored.voipToken { return .tokenChanged }
        if stored.userId != current.userId { return .userChanged }
        // A clock moved backwards also counts as elapsed, so a bad clock can't
        // suppress refreshes forever.
        let elapsed = now.timeIntervalSince(lastSuccess)
        if elapsed >= interval || elapsed < 0 { return .intervalElapsed }
        return nil
    }
}
