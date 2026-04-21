import XCTest
@testable import RiviumPush

/// Unit tests for RiviumPushConfig
final class RiviumPushConfigTests: XCTestCase {

    // MARK: - Builder Pattern Tests

    func testBuilder_minimalConfig() {
        let config = RiviumPushConfig.builder(apiKey: "test_api_key").build()

        XCTAssertEqual(config.apiKey, "test_api_key")
        XCTAssertEqual(config.serverUrl, "https://push-api.rivium.co")
    }

    func testBuilder_customServerUrl() {
        let config = RiviumPushConfig.builder(apiKey: "test_key")
            .serverUrl("https://custom.api.com")
            .build()

        XCTAssertEqual(config.serverUrl, "https://custom.api.com")
    }

    func testBuilder_usePushKit() {
        let config = RiviumPushConfig.builder(apiKey: "test_key")
            .usePushKit(true)
            .build()

        XCTAssertTrue(config.usePushKit)
    }

    func testBuilder_usePushKitFalse() {
        let config = RiviumPushConfig.builder(apiKey: "test_key")
            .usePushKit(false)
            .build()

        XCTAssertFalse(config.usePushKit)
    }

    func testBuilder_showNotificationInForeground() {
        let config = RiviumPushConfig.builder(apiKey: "test_key")
            .showNotificationInForeground(true)
            .build()

        XCTAssertTrue(config.showNotificationInForeground)
    }

    func testBuilder_autoConnect() {
        let config = RiviumPushConfig.builder(apiKey: "test_key")
            .autoConnect(true)
            .build()

        XCTAssertTrue(config.autoConnect)
    }

    func testBuilder_autoConnectFalse() {
        let config = RiviumPushConfig.builder(apiKey: "test_key")
            .autoConnect(false)
            .build()

        XCTAssertFalse(config.autoConnect)
    }

    func testBuilder_autoReconnect() {
        let configEnabled = RiviumPushConfig.builder(apiKey: "test_key")
            .autoReconnect(true)
            .build()

        XCTAssertTrue(configEnabled.autoReconnect)

        let configDisabled = RiviumPushConfig.builder(apiKey: "test_key")
            .autoReconnect(false)
            .build()

        XCTAssertFalse(configDisabled.autoReconnect)
    }

    func testBuilder_chainedConfiguration() {
        let config = RiviumPushConfig.builder(apiKey: "test_key")
            .serverUrl("https://staging.api.com")
            .usePushKit(false)
            .showNotificationInForeground(true)
            .autoConnect(true)
            .autoReconnect(false)
            .maxReconnectAttempts(5)
            .build()

        XCTAssertEqual(config.apiKey, "test_key")
        XCTAssertEqual(config.serverUrl, "https://staging.api.com")
        XCTAssertFalse(config.usePushKit)
        XCTAssertTrue(config.showNotificationInForeground)
        XCTAssertTrue(config.autoConnect)
        XCTAssertFalse(config.autoReconnect)
        XCTAssertEqual(config.maxReconnectAttempts, 5)
    }

    // MARK: - API Key Validation

    func testApiKey_notEmpty() {
        let config = RiviumPushConfig.builder(apiKey: "rv_live_abc123").build()
        XCTAssertFalse(config.apiKey.isEmpty)
    }

    func testApiKey_preservesValue() {
        let apiKey = "rv_live_1234567890abcdef"
        let config = RiviumPushConfig.builder(apiKey: apiKey).build()
        XCTAssertEqual(config.apiKey, apiKey)
    }

    // MARK: - Server URL Tests

    func testServerUrl_defaultValue() {
        let config = RiviumPushConfig.builder(apiKey: "test").build()
        XCTAssertEqual(config.serverUrl, "https://push-api.rivium.co")
    }

    func testServerUrl_customValue() {
        let config = RiviumPushConfig.builder(apiKey: "test")
            .serverUrl("https://api.staging.rivium.co")
            .build()

        XCTAssertEqual(config.serverUrl, "https://api.staging.rivium.co")
    }

    func testServerUrl_withTrailingSlash() {
        // The config should handle URLs regardless of trailing slash
        let config = RiviumPushConfig.builder(apiKey: "test")
            .serverUrl("https://api.example.com/")
            .build()

        // The URL is stored as-is
        XCTAssertEqual(config.serverUrl, "https://api.example.com/")
    }

    // MARK: - Default Values Tests

    func testDefaultValues() {
        let config = RiviumPushConfig.builder(apiKey: "test").build()

        // Verify defaults (these may vary based on implementation)
        XCTAssertEqual(config.serverUrl, "https://push-api.rivium.co")
    }
}
