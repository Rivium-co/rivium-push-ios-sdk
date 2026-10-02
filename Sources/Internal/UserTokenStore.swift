import Foundation
import Security

/// Where the last user token is kept between launches.
///
/// Nothing here throws or blocks on user interaction: a failed read means
/// "nothing stored" and a failed write means "not stored".
internal protocol UserTokenStore {
    /// The stored token, or nil when there is none or it cannot be read.
    func read() -> String?
    /// Returns false when the token could not be stored.
    @discardableResult func write(_ token: String) -> Bool
    /// Returns false when a stored token could not be removed.
    @discardableResult func remove() -> Bool
}

/// Keeps the token in the Keychain as a generic password.
///
/// Readable in the background once the device has been unlocked after a
/// restart, and never part of a backup or a transfer to another device. Uses
/// the app's default access group, so it needs no entitlement or setup.
internal struct KeychainUserTokenStore: UserTokenStore {
    static let defaultService = "co.rivium.push"
    static let defaultAccount = "userToken"

    private static let tag = "UserToken"

    let service: String
    let account: String

    init(
        service: String = KeychainUserTokenStore.defaultService,
        account: String = KeychainUserTokenStore.defaultAccount
    ) {
        self.service = service
        self.account = account
    }

    private var itemQuery: [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func read() -> String? {
        var query = itemQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            if status != errSecItemNotFound { report("read", status) }
            return nil
        }
        guard let data = result as? Data, let token = String(data: data, encoding: .utf8), !token.isEmpty else {
            return nil
        }
        return token
    }

    @discardableResult
    func write(_ token: String) -> Bool {
        let attributes: [String: Any] = [
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        var status = SecItemUpdate(itemQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(itemQuery.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        if status != errSecSuccess { report("write", status) }
        return status == errSecSuccess
    }

    @discardableResult
    func remove() -> Bool {
        let status = SecItemDelete(itemQuery as CFDictionary)
        let removed = status == errSecSuccess || status == errSecItemNotFound
        if !removed { report("remove", status) }
        return removed
    }

    private func report(_ operation: String, _ status: OSStatus) {
        Log.d(KeychainUserTokenStore.tag, "Keychain \(operation) failed (status \(status))")
    }
}
