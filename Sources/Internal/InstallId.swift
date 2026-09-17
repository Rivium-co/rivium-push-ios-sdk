import Foundation
import CryptoKit
#if canImport(UIKit)
import UIKit
#endif

/// Stable per-install fingerprint sent with device registration.
///
/// The locally stored `deviceId` is random: a reinstall or a fresh build mints
/// a new one and the server keeps the old row active for ever, so one phone
/// counts as several devices and delivery rates read too low. `installId` lets
/// the server recognise the install and retire the previous row.
///
/// The value is `sha256("<identifierForVendor>:<bundleIdentifier>")`, hex,
/// truncated to 32 lowercase characters — the same shape the Android SDK sends
/// for `sha256("<ANDROID_ID>:<packageName>")`. `identifierForVendor` survives
/// app updates, and survives a reinstall while another app from the same
/// vendor stays installed; it is the most stable per-install id Apple allows.
///
/// The raw `identifierForVendor` never leaves the device — only its hash, so
/// the value cannot be turned back into an Apple-issued device identifier or
/// correlated with anything outside this vendor's apps.
internal enum InstallId {

    /// Hash `vendorId` and `bundleId` into the value the backend accepts
    /// (`^[a-f0-9]{8,64}$`). Returns nil when either input is missing or
    /// empty, so the field is omitted rather than sent blank.
    static func compute(vendorId: String?, bundleId: String?) -> String? {
        guard let vendorId = vendorId, !vendorId.isEmpty,
              let bundleId = bundleId, !bundleId.isEmpty else { return nil }

        let digest = SHA256.hash(data: Data("\(vendorId):\(bundleId)".utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(32))
    }

    private static let lock = NSLock()
    private static var cached: String?

    /// The install id for this app, computed once and kept in memory.
    ///
    /// `identifierForVendor` is nil shortly after boot, before the device is
    /// first unlocked. Nothing is cached then, so the next registration tries
    /// again instead of omitting the field for the rest of the process.
    static var current: String? {
        #if canImport(UIKit)
        lock.lock()
        defer { lock.unlock() }
        if let cached = cached { return cached }
        let value = compute(
            vendorId: UIDevice.current.identifierForVendor?.uuidString,
            bundleId: Bundle.main.bundleIdentifier
        )
        cached = value
        return value
        #else
        return nil
        #endif
    }
}
