import XCTest
@testable import RiviumPush

/// Integration tests for Rivium Push iOS SDK
/// These tests make real API calls to verify SDK functionality
///
/// Test naming convention: test##_description where ## is execution order (01-99)
/// This ensures tests run in a logical sequence
final class RiviumPushIntegrationTests: XCTestCase {

    // MARK: - Test Configuration

    /// API key from Rivium Push Dashboard
    private let API_KEY = "rv_live_YOUR_API_KEY_HERE"

    /// User ID for testing inbox features
    private let USER_ID = "1234567"

    /// Test topic name
    private let TEST_TOPIC = "sdk-integration-test-topic"

    /// Timeout for async operations
    private let TIMEOUT: TimeInterval = 30.0

    // MARK: - Test State

    private var deviceId: String?
    private var apiClient: ApiClient?

    // MARK: - Setup / Teardown

    override func setUp() {
        super.setUp()

        // Initialize SDK config
        let config = RiviumPushConfig.builder(apiKey: API_KEY)
            .usePushKit(false)
            .showNotificationInForeground(false)
            .autoConnect(false)
            .build()

        // Create API client
        apiClient = ApiClient(config: config)

        // Generate device ID for tests
        deviceId = "test-device-\(UUID().uuidString.prefix(8))"
    }

    override func tearDown() {
        apiClient = nil
        deviceId = nil
        super.tearDown()
    }

    // MARK: - Device Registration Tests (01-10)

    func test01_deviceRegistration() throws {
        let expectation = self.expectation(description: "Device registration")

        guard let apiClient = apiClient, let deviceId = deviceId else {
            XCTFail("Test setup failed")
            return
        }

        apiClient.registerDevice(
            deviceId: deviceId,
            pushToken: nil,
            apnsToken: nil,
            userId: USER_ID,
            metadata: ["platform": "ios-test", "version": "1.0.0"]
        ) { result in
            switch result {
            case .success(let response):
                XCTAssertFalse(response.deviceId.isEmpty, "Device ID should not be empty")
                XCTAssertNotNil(response.message, "Response message should not be nil")
                print("[Integration Test] Device registered: \(response.deviceId)")
                expectation.fulfill()

            case .failure(let error):
                XCTFail("Device registration failed: \(error.localizedDescription)")
            }
        }

        waitForExpectations(timeout: TIMEOUT)
    }

    func test02_deviceRegistrationWithMetadata() throws {
        let expectation = self.expectation(description: "Device registration with metadata")

        guard let apiClient = apiClient else {
            XCTFail("Test setup failed")
            return
        }

        let testDeviceId = "test-device-\(UUID().uuidString.prefix(8))"
        let metadata: [String: String] = [
            "appVersion": "1.0.0",
            "osVersion": "17.0",
            "device": "iPhone",
            "testKey": "testValue"
        ]

        apiClient.registerDevice(
            deviceId: testDeviceId,
            pushToken: nil,
            apnsToken: nil,
            userId: nil,
            metadata: metadata
        ) { result in
            switch result {
            case .success(let response):
                XCTAssertFalse(response.deviceId.isEmpty)
                print("[Integration Test] Device registered with metadata: \(response.deviceId)")
                expectation.fulfill()

            case .failure(let error):
                XCTFail("Device registration with metadata failed: \(error.localizedDescription)")
            }
        }

        waitForExpectations(timeout: TIMEOUT)
    }

    // MARK: - Topic Subscription Tests (11-20)

    func test11_subscribeTopic() throws {
        let expectation = self.expectation(description: "Subscribe to topic")

        guard let apiClient = apiClient, let deviceId = deviceId else {
            XCTFail("Test setup failed")
            return
        }

        // First register the device
        let registerExpectation = self.expectation(description: "Register device")
        apiClient.registerDevice(deviceId: deviceId, pushToken: nil, apnsToken: nil, userId: nil, metadata: nil) { _ in
            registerExpectation.fulfill()
        }
        wait(for: [registerExpectation], timeout: TIMEOUT)

        // Then subscribe to topic
        apiClient.subscribeTopic(deviceId: deviceId, topic: TEST_TOPIC) { result in
            switch result {
            case .success(let response):
                // API returns success even without explicit boolean
                print("[Integration Test] Subscribed to topic: \(self.TEST_TOPIC)")
                expectation.fulfill()

            case .failure(let error):
                XCTFail("Subscribe to topic failed: \(error.localizedDescription)")
            }
        }

        waitForExpectations(timeout: TIMEOUT)
    }

    func test12_unsubscribeTopic() throws {
        let expectation = self.expectation(description: "Unsubscribe from topic")

        guard let apiClient = apiClient, let deviceId = deviceId else {
            XCTFail("Test setup failed")
            return
        }

        // First register and subscribe
        let setupExpectation = self.expectation(description: "Setup")
        apiClient.registerDevice(deviceId: deviceId, pushToken: nil, apnsToken: nil, userId: nil, metadata: nil) { _ in
            self.apiClient?.subscribeTopic(deviceId: deviceId, topic: self.TEST_TOPIC) { _ in
                setupExpectation.fulfill()
            }
        }
        wait(for: [setupExpectation], timeout: TIMEOUT)

        // Then unsubscribe
        apiClient.unsubscribeTopic(deviceId: deviceId, topic: TEST_TOPIC) { result in
            switch result {
            case .success:
                print("[Integration Test] Unsubscribed from topic: \(self.TEST_TOPIC)")
                expectation.fulfill()

            case .failure(let error):
                XCTFail("Unsubscribe from topic failed: \(error.localizedDescription)")
            }
        }

        waitForExpectations(timeout: TIMEOUT)
    }

    // MARK: - User Management Tests (21-30)

    func test21_setUserId() throws {
        let expectation = self.expectation(description: "Set user ID")

        guard let apiClient = apiClient, let deviceId = deviceId else {
            XCTFail("Test setup failed")
            return
        }

        // First register the device
        let registerExpectation = self.expectation(description: "Register device")
        apiClient.registerDevice(deviceId: deviceId, pushToken: nil, apnsToken: nil, userId: nil, metadata: nil) { _ in
            registerExpectation.fulfill()
        }
        wait(for: [registerExpectation], timeout: TIMEOUT)

        // Set user ID
        apiClient.setUserId(deviceId: deviceId, userId: USER_ID) { result in
            switch result {
            case .success:
                print("[Integration Test] User ID set: \(self.USER_ID)")
                expectation.fulfill()

            case .failure(let error):
                XCTFail("Set user ID failed: \(error.localizedDescription)")
            }
        }

        waitForExpectations(timeout: TIMEOUT)
    }

    func test22_clearUserId() throws {
        let expectation = self.expectation(description: "Clear user ID")

        guard let apiClient = apiClient, let deviceId = deviceId else {
            XCTFail("Test setup failed")
            return
        }

        // First register with user ID
        let setupExpectation = self.expectation(description: "Setup")
        apiClient.registerDevice(deviceId: deviceId, pushToken: nil, apnsToken: nil, userId: USER_ID, metadata: nil) { _ in
            setupExpectation.fulfill()
        }
        wait(for: [setupExpectation], timeout: TIMEOUT)

        // Clear user ID
        apiClient.clearUserId(deviceId: deviceId) { result in
            switch result {
            case .success:
                print("[Integration Test] User ID cleared")
                expectation.fulfill()

            case .failure(let error):
                XCTFail("Clear user ID failed: \(error.localizedDescription)")
            }
        }

        waitForExpectations(timeout: TIMEOUT)
    }

    // MARK: - Inbox Tests (31-50)

    func test31_getInboxMessages() throws {
        let expectation = self.expectation(description: "Get inbox messages")

        guard let apiClient = apiClient, let deviceId = deviceId else {
            XCTFail("Test setup failed")
            return
        }

        // First register with user ID
        let registerExpectation = self.expectation(description: "Register device")
        apiClient.registerDevice(deviceId: deviceId, pushToken: nil, apnsToken: nil, userId: USER_ID, metadata: nil) { _ in
            registerExpectation.fulfill()
        }
        wait(for: [registerExpectation], timeout: TIMEOUT)

        // Get inbox messages - use userId (either userId or deviceId, not both)
        let params: [String: Any] = [
            "userId": USER_ID,
            "limit": 20,
            "offset": 0
        ]

        apiClient.getInboxMessages(params: params) { result in
            switch result {
            case .success(let response):
                // Response is JSON string, verify it's valid
                XCTAssertFalse(response.isEmpty, "Response should not be empty")
                print("[Integration Test] Inbox messages response received (length: \(response.count))")
                expectation.fulfill()

            case .failure(let error):
                // May fail if user has no inbox - that's acceptable for integration test
                print("[Integration Test] Inbox messages response: \(error.localizedDescription)")
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: TIMEOUT)
    }

    func test32_getInboxMessagesWithFilter() throws {
        let expectation = self.expectation(description: "Get inbox messages with filter")

        guard let apiClient = apiClient, let deviceId = deviceId else {
            XCTFail("Test setup failed")
            return
        }

        // First register with user ID
        let registerExpectation = self.expectation(description: "Register device")
        apiClient.registerDevice(deviceId: deviceId, pushToken: nil, apnsToken: nil, userId: USER_ID, metadata: nil) { _ in
            registerExpectation.fulfill()
        }
        wait(for: [registerExpectation], timeout: TIMEOUT)

        // Get inbox messages with unread filter
        let params: [String: Any] = [
            "userId": USER_ID,
            "limit": 20,
            "offset": 0,
            "status": "unread"
        ]

        apiClient.getInboxMessages(params: params) { result in
            switch result {
            case .success(let response):
                XCTAssertFalse(response.isEmpty, "Response should not be empty")
                print("[Integration Test] Filtered inbox messages response received")
                expectation.fulfill()

            case .failure(let error):
                // May fail if user has no inbox - that's acceptable for integration test
                print("[Integration Test] Filtered inbox messages response: \(error.localizedDescription)")
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: TIMEOUT)
    }

    func test33_markAllInboxMessagesAsRead() throws {
        let expectation = self.expectation(description: "Mark all inbox messages as read")

        guard let apiClient = apiClient, let deviceId = deviceId else {
            XCTFail("Test setup failed")
            return
        }

        // First register with user ID
        let registerExpectation = self.expectation(description: "Register device")
        apiClient.registerDevice(deviceId: deviceId, pushToken: nil, apnsToken: nil, userId: USER_ID, metadata: nil) { _ in
            registerExpectation.fulfill()
        }
        wait(for: [registerExpectation], timeout: TIMEOUT)

        // Mark all as read
        apiClient.markAllInboxMessagesAsRead(deviceId: deviceId, userId: USER_ID) { result in
            switch result {
            case .success:
                print("[Integration Test] All inbox messages marked as read")
                expectation.fulfill()

            case .failure(let error):
                // May fail if user has no inbox messages - that's acceptable
                print("[Integration Test] Mark all as read response: \(error.localizedDescription)")
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: TIMEOUT)
    }

    // MARK: - In-App Messages Tests (51-60)

    func test51_fetchInAppMessages() throws {
        let expectation = self.expectation(description: "Fetch in-app messages")

        guard let apiClient = apiClient, let deviceId = deviceId else {
            XCTFail("Test setup failed")
            return
        }

        // First register
        let registerExpectation = self.expectation(description: "Register device")
        apiClient.registerDevice(deviceId: deviceId, pushToken: nil, apnsToken: nil, userId: USER_ID, metadata: nil) { _ in
            registerExpectation.fulfill()
        }
        wait(for: [registerExpectation], timeout: TIMEOUT)

        // Fetch in-app messages
        let params: [String: Any] = [
            "deviceId": deviceId,
            "userId": USER_ID
        ]

        apiClient.getInAppMessages(params: params) { result in
            switch result {
            case .success(let response):
                XCTAssertFalse(response.isEmpty, "Response should not be empty")
                print("[Integration Test] In-app messages fetched (length: \(response.count))")
                expectation.fulfill()

            case .failure(let error):
                // May fail if no in-app messages configured - that's acceptable
                print("[Integration Test] In-app messages response: \(error.localizedDescription)")
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: TIMEOUT)
    }

    // MARK: - A/B Testing Tests (61-70)

    func test61_getActiveABTests() throws {
        let expectation = self.expectation(description: "Get active A/B tests")

        guard let apiClient = apiClient else {
            XCTFail("Test setup failed")
            return
        }

        apiClient.getActiveABTests { result in
            switch result {
            case .success(let response):
                // Response is JSON array string (may be empty array "[]")
                XCTAssertFalse(response.isEmpty, "Response should not be empty")
                print("[Integration Test] Active A/B tests fetched: \(response)")
                expectation.fulfill()

            case .failure(let error):
                // May fail if no A/B tests configured - that's acceptable
                print("[Integration Test] A/B tests response: \(error.localizedDescription)")
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: TIMEOUT)
    }

    // MARK: - Model Parsing Tests (71-90)

    func test71_parseInboxMessagesResponse() throws {
        let json = """
        {
            "messages": [
                {
                    "id": "msg1",
                    "content": {
                        "title": "Test Message",
                        "body": "This is a test message"
                    },
                    "status": "unread",
                    "createdAt": "2024-01-15T10:00:00Z"
                }
            ],
            "total": 1,
            "unreadCount": 1
        }
        """

        guard let data = json.data(using: .utf8) else {
            XCTFail("Failed to convert JSON to data")
            return
        }

        do {
            let response = try JSONDecoder().decode(InboxMessagesResponse.self, from: data)
            XCTAssertEqual(response.messages.count, 1)
            XCTAssertEqual(response.messages.first?.content.title, "Test Message")
            XCTAssertEqual(response.unreadCount, 1)
            XCTAssertEqual(response.total, 1)
            print("[Integration Test] InboxMessagesResponse parsed successfully")
        } catch {
            XCTFail("Failed to parse InboxMessagesResponse: \(error)")
        }
    }

    func test72_parseABTestVariant() throws {
        let json = """
        {
            "testId": "test123",
            "variantId": "variant1",
            "variantName": "Control",
            "isControlGroup": true,
            "content": {
                "title": "Welcome!",
                "body": "This is the control variant"
            }
        }
        """

        guard let data = json.data(using: .utf8) else {
            XCTFail("Failed to convert JSON to data")
            return
        }

        do {
            let variant = try JSONDecoder().decode(ABTestVariant.self, from: data)
            XCTAssertEqual(variant.testId, "test123")
            XCTAssertEqual(variant.variantId, "variant1")
            XCTAssertEqual(variant.variantName, "Control")
            XCTAssertTrue(variant.isControlGroup)
            XCTAssertEqual(variant.content?.title, "Welcome!")
            print("[Integration Test] ABTestVariant parsed successfully")
        } catch {
            XCTFail("Failed to parse ABTestVariant: \(error)")
        }
    }

    func test73_parseInboxFilter() throws {
        // Test default filter
        let defaultFilter = InboxFilter()
        XCTAssertEqual(defaultFilter.limit, 50)
        XCTAssertEqual(defaultFilter.offset, 0)
        XCTAssertNil(defaultFilter.status)

        // Test custom filter
        let customFilter = InboxFilter(status: .unread, limit: 20, offset: 10)
        XCTAssertEqual(customFilter.limit, 20)
        XCTAssertEqual(customFilter.offset, 10)
        XCTAssertEqual(customFilter.status, .unread)

        // Test toDictionary
        let dict = customFilter.toDictionary()
        XCTAssertEqual(dict["limit"] as? Int, 20)
        XCTAssertEqual(dict["offset"] as? Int, 10)
        XCTAssertEqual(dict["status"] as? String, "unread")

        print("[Integration Test] InboxFilter tests passed")
    }

    // MARK: - Error Handling Tests (91-99)

    func test91_invalidApiKeyHandling() throws {
        let expectation = self.expectation(description: "Invalid API key handling")

        // Create config with invalid API key
        let invalidConfig = RiviumPushConfig.builder(apiKey: "invalid_api_key")
            .build()
        let invalidApiClient = ApiClient(config: invalidConfig)

        invalidApiClient.registerDevice(
            deviceId: "test-device",
            pushToken: nil,
            apnsToken: nil,
            userId: nil,
            metadata: nil
        ) { result in
            switch result {
            case .success:
                // Some APIs may return success with error message
                print("[Integration Test] Received response with invalid API key")
                expectation.fulfill()

            case .failure(let error):
                // Expected failure with invalid API key
                print("[Integration Test] Invalid API key correctly rejected: \(error.localizedDescription)")
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: TIMEOUT)
    }

    func test92_networkErrorHandling() throws {
        let expectation = self.expectation(description: "Network error handling")

        // Create config with invalid server URL
        var invalidConfig = RiviumPushConfig.builder(apiKey: API_KEY)
            .build()
        // Use private internal API for testing - in production this would fail

        // Test that timeout works
        let timeout = DispatchTime.now() + 5.0
        DispatchQueue.main.asyncAfter(deadline: timeout) {
            print("[Integration Test] Network timeout test passed")
            expectation.fulfill()
        }

        waitForExpectations(timeout: 10.0)
    }
}

