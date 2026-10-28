import XCTest
@testable import RiviumPush

/// Opened / clicked / dismissed receipts: which response means what, and the
/// request each one sends.
final class NotificationInteractionTests: XCTestCase {

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: configuration)
    }

    override func tearDown() {
        MockURLProtocol.reset()
        session = nil
        super.tearDown()
    }

    func testActionIdentifierMapping() {
        XCTAssertEqual(NotificationInteraction.from(actionIdentifier: nil), .opened)
        XCTAssertEqual(NotificationInteraction.from(actionIdentifier: "com.apple.UNNotificationDefaultActionIdentifier"), .opened)
        XCTAssertEqual(NotificationInteraction.from(actionIdentifier: "com.apple.UNNotificationDismissActionIdentifier"), .dismissed)
        XCTAssertEqual(NotificationInteraction.from(actionIdentifier: "reply"), .clicked)
        XCTAssertEqual(NotificationInteraction.from(actionIdentifier: "com.apple.UNNotificationDefaultActionIdentifier"),
                       NotificationInteraction.from(actionIdentifier: NotificationInteraction.defaultActionIdentifier))
    }

    private func bodyJSON(_ request: URLRequest) -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private func send(endpoint: String, extra: [String: String] = [:]) -> (URLRequest?, Bool) {
        var seen: URLRequest?
        MockURLProtocol.requestHandler = { request in
            seen = request
            return MockURLProtocol.mockResponse(statusCode: 200, json: ["success": true])
        }
        let done = expectation(description: "sent")
        var ok = false
        DeliveryReceiptSender.send(
            messageId: "m1",
            deviceId: "d1",
            apiKey: "rv_live_test",
            serverUrl: "https://push.example.com",
            sdkHeader: "ios/1.0.0",
            userToken: "user-token",
            maxAttempts: 1,
            timeout: 5,
            session: session,
            endpoint: endpoint,
            extraFields: extra
        ) { success in
            ok = success
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return (seen, ok)
    }

    func testDeliveredRequestIsUnchangedByDefault() {
        var seen: URLRequest?
        MockURLProtocol.requestHandler = { request in
            seen = request
            return MockURLProtocol.mockResponse(statusCode: 200, json: [:])
        }
        let done = expectation(description: "sent")
        DeliveryReceiptSender.send(
            messageId: "m1", deviceId: "d1", apiKey: "k", serverUrl: "https://push.example.com",
            sdkHeader: "ios/1.0.0", maxAttempts: 1, timeout: 5, session: session
        ) { _ in done.fulfill() }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(seen?.url?.absoluteString, "https://push.example.com/receipts/delivered")
        XCTAssertEqual(bodyJSON(seen!).keys.sorted(), ["deviceId", "messageId"])
    }

    func testOpenedReceiptCarriesSameHeadersAsDelivered() {
        let (request, ok) = send(endpoint: NotificationInteraction.opened.rawValue)
        XCTAssertTrue(ok)
        XCTAssertEqual(request?.httpMethod, "POST")
        XCTAssertEqual(request?.url?.absoluteString, "https://push.example.com/receipts/opened")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "x-api-key"), "rv_live_test")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "x-user-token"), "user-token")
        XCTAssertEqual(request?.value(forHTTPHeaderField: RiviumPushSDKInfo.headerName), "ios/1.0.0")
        let body = bodyJSON(request!)
        XCTAssertEqual(body["messageId"] as? String, "m1")
        XCTAssertEqual(body["deviceId"] as? String, "d1")
        XCTAssertNil(body["actionId"])
    }

    func testClickedReceiptCarriesActionId() {
        let (request, _) = send(endpoint: NotificationInteraction.clicked.rawValue, extra: ["actionId": "reply"])
        XCTAssertEqual(request?.url?.path, "/receipts/clicked")
        XCTAssertEqual(bodyJSON(request!)["actionId"] as? String, "reply")
    }

    func testReportNotificationResponseIsReachableFromObjectiveC() {
        // Cross-platform plugins look it up at run time.
        XCTAssertTrue(RiviumPush.instancesRespond(to: NSSelectorFromString("reportNotificationResponseWithUserInfo:actionIdentifier:")))
    }

    func testDismissedReceiptEndpoint() {
        let (request, _) = send(endpoint: NotificationInteraction.dismissed.rawValue)
        XCTAssertEqual(request?.url?.path, "/receipts/dismissed")
    }
}
