import XCTest
@testable import RiviumPush

final class SdkIdentityTests: XCTestCase {

    func testSdkVersionMatchesPodspecs() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        for name in ["RiviumPushSDK.podspec", "RiviumPushSDKExtension.podspec"] {
            let spec = try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
            XCTAssertTrue(
                spec.contains("s.version          = '\(RiviumPush.sdkVersion)'"),
                "\(name) version does not match RiviumPush.sdkVersion (\(RiviumPush.sdkVersion))"
            )
        }
    }

    func testDefaultIdentityIsNativeIos() {
        let config = RiviumPushConfig(apiKey: "k")
        XCTAssertEqual(config.reportedSdkName, "ios")
        XCTAssertEqual(config.reportedSdkVersion, RiviumPush.sdkVersion)
        XCTAssertEqual(config.sdkHeaderValue, "ios/\(RiviumPush.sdkVersion)")
        XCTAssertTrue(config.autoRefresh)
    }

    func testWrapperIdentityReplacesNative() {
        let config = RiviumPushConfig.builder(apiKey: "k").wrapperSdk(name: "flutter", version: "0.1.16").build()
        XCTAssertEqual(config.sdkHeaderValue, "flutter/0.1.16")
    }

    func testWrapperIdentityNeedsBothFields() {
        let config = RiviumPushConfig(apiKey: "k", wrapperSdkName: "flutter")
        XCTAssertEqual(config.reportedSdkName, "ios")
    }

    func testSanitize() {
        XCTAssertEqual(RiviumPushSDKInfo.sanitize("react native!"), "reactnative")
        XCTAssertEqual(RiviumPushSDKInfo.sanitize(String(repeating: "a", count: 40))?.count, 32)
        XCTAssertNil(RiviumPushSDKInfo.sanitize("  "))
        XCTAssertEqual(RiviumPushSDKInfo.sanitize("1.0.0-beta+2"), "1.0.0-beta+2")
    }
}

final class RegistrationRefreshTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let base = RegistrationFingerprint(
        appVersion: "2.0", appBuild: "18", sdkIdentity: "ios/0.1.12",
        apnsToken: "aa", voipToken: nil, userId: "u1"
    )

    private func reason(
        hasRegistered: Bool = true,
        ago: TimeInterval = 60,
        stored: RegistrationFingerprint? = nil,
        current: RegistrationFingerprint? = nil
    ) -> RegistrationRefresh.Reason? {
        RegistrationRefresh.reason(
            hasRegistered: hasRegistered,
            lastSuccess: now.addingTimeInterval(-ago),
            now: now,
            stored: stored ?? base,
            current: current ?? base
        )
    }

    func testNeverRegisteredSkips() { XCTAssertNil(reason(hasRegistered: false, ago: 1e9)) }
    func testUnchangedRecentSkips() { XCTAssertNil(reason()) }
    func testIntervalElapsed() { XCTAssertEqual(reason(ago: 24 * 3600), .intervalElapsed) }
    func testClockBackwards() { XCTAssertEqual(reason(ago: -3600), .intervalElapsed) }

    func testMissingRecord() {
        XCTAssertEqual(
            RegistrationRefresh.reason(hasRegistered: true, lastSuccess: nil, now: now, stored: nil, current: base),
            .neverRecorded
        )
    }

    func testAppVersionOrBuildChanged() {
        var c = base; c.appVersion = "2.1"
        XCTAssertEqual(reason(current: c), .appVersionChanged)
        c = base; c.appBuild = "19"
        XCTAssertEqual(reason(current: c), .appVersionChanged)
    }

    func testSdkChanged() {
        var c = base; c.sdkIdentity = "flutter/0.1.16"
        XCTAssertEqual(reason(current: c), .sdkChanged)
    }

    func testTokenChanged() {
        var c = base; c.apnsToken = "bb"
        XCTAssertEqual(reason(current: c), .tokenChanged)
        c = base; c.voipToken = "vv"
        XCTAssertEqual(reason(current: c), .tokenChanged)
    }

    func testUnknownTokenIsNotAChange() {
        var c = base; c.apnsToken = nil
        XCTAssertNil(reason(current: c))
    }

    func testUserChanged() {
        var c = base; c.userId = nil
        XCTAssertEqual(reason(current: c), .userChanged)
    }
}

final class DeliveryReceiptTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "co.rivium.push.tests.receipts"

    override func setUp() {
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
    }

    func testClaimOnce() {
        let store = DeliveryReceiptStore(defaults: defaults)
        XCTAssertTrue(store.claim("m1"))
        XCTAssertFalse(store.claim("m1"))
    }

    func testClaimSharedAcrossInstances() {
        // App and extension each build their own store over the App Group.
        XCTAssertTrue(DeliveryReceiptStore(defaults: defaults).claim("m1"))
        XCTAssertFalse(DeliveryReceiptStore(defaults: defaults).claim("m1"))
    }

    func testReleaseAllowsRetry() {
        let store = DeliveryReceiptStore(defaults: defaults)
        XCTAssertTrue(store.claim("m1"))
        store.release("m1")
        XCTAssertTrue(store.claim("m1"))
    }

    func testBoundedEvictsOldest() {
        let store = DeliveryReceiptStore(defaults: defaults, capacity: 3)
        for id in ["a", "b", "c", "d"] { XCTAssertTrue(store.claim(id)) }
        XCTAssertFalse(store.contains("a"))
        XCTAssertTrue(store.contains("d"))
        XCTAssertEqual(defaults.stringArray(forKey: DeliveryReceiptStore.storageKey)?.count, 3)
    }

    func testTransientClassification() {
        XCTAssertTrue(DeliveryReceiptSender.isTransient(statusCode: 503, error: nil))
        XCTAssertTrue(DeliveryReceiptSender.isTransient(statusCode: 429, error: nil))
        XCTAssertFalse(DeliveryReceiptSender.isTransient(statusCode: 400, error: nil))
        XCTAssertFalse(DeliveryReceiptSender.isTransient(statusCode: 404, error: nil))
        XCTAssertTrue(DeliveryReceiptSender.isTransient(statusCode: nil, error: URLError(.notConnectedToInternet)))
        XCTAssertEqual(DeliveryReceiptSender.backoff(forRetry: 1), 1)
        XCTAssertEqual(DeliveryReceiptSender.backoff(forRetry: 2), 2)
        XCTAssertEqual(DeliveryReceiptSender.backoff(forRetry: 10), 8)
    }

    func testMessageIdExtraction() {
        XCTAssertEqual(RiviumPushServiceExtension.messageId(from: ["rivium_push_message": ["messageId": "x"]]), "x")
        XCTAssertEqual(RiviumPushServiceExtension.messageId(from: ["messageId": "y"]), "y")
        XCTAssertNil(RiviumPushServiceExtension.messageId(from: ["aps": [:]]))
    }
}
