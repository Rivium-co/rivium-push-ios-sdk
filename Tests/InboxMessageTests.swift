import XCTest
@testable import RiviumPush

/// Unit tests for InboxMessage model and related types
final class InboxMessageTests: XCTestCase {

    // MARK: - InboxMessageStatus Tests

    func testInboxMessageStatus_fromString_validValues() {
        XCTAssertEqual(InboxMessageStatus.fromString("unread"), .unread)
        XCTAssertEqual(InboxMessageStatus.fromString("read"), .read)
        XCTAssertEqual(InboxMessageStatus.fromString("archived"), .archived)
        XCTAssertEqual(InboxMessageStatus.fromString("deleted"), .deleted)
    }

    func testInboxMessageStatus_fromString_caseInsensitive() {
        XCTAssertEqual(InboxMessageStatus.fromString("UNREAD"), .unread)
        XCTAssertEqual(InboxMessageStatus.fromString("Read"), .read)
        XCTAssertEqual(InboxMessageStatus.fromString("ARCHIVED"), .archived)
    }

    func testInboxMessageStatus_fromString_invalidReturnsUnread() {
        XCTAssertEqual(InboxMessageStatus.fromString("invalid"), .unread)
        XCTAssertEqual(InboxMessageStatus.fromString(""), .unread)
    }

    func testInboxMessageStatus_rawValues() {
        XCTAssertEqual(InboxMessageStatus.unread.rawValue, "unread")
        XCTAssertEqual(InboxMessageStatus.read.rawValue, "read")
        XCTAssertEqual(InboxMessageStatus.archived.rawValue, "archived")
        XCTAssertEqual(InboxMessageStatus.deleted.rawValue, "deleted")
    }

    // MARK: - InboxContent Tests

    func testInboxContent_initMinimal() {
        let content = InboxContent(title: "Test Title", body: "Test Body")

        XCTAssertEqual(content.title, "Test Title")
        XCTAssertEqual(content.body, "Test Body")
        XCTAssertNil(content.imageUrl)
        XCTAssertNil(content.iconUrl)
        XCTAssertNil(content.deepLink)
        XCTAssertNil(content.data)
    }

    func testInboxContent_initFull() {
        let content = InboxContent(
            title: "Title",
            body: "Body",
            imageUrl: "https://example.com/image.png",
            iconUrl: "https://example.com/icon.png",
            deepLink: "myapp://action",
            data: ["key": AnyCodable("value")]
        )

        XCTAssertEqual(content.title, "Title")
        XCTAssertEqual(content.body, "Body")
        XCTAssertEqual(content.imageUrl, "https://example.com/image.png")
        XCTAssertEqual(content.iconUrl, "https://example.com/icon.png")
        XCTAssertEqual(content.deepLink, "myapp://action")
        XCTAssertNotNil(content.data)
    }

    func testInboxContent_toDictionary() {
        let content = InboxContent(
            title: "Test",
            body: "Body",
            imageUrl: "https://example.com/image.png"
        )

        let dict = content.toDictionary()

        XCTAssertEqual(dict["title"] as? String, "Test")
        XCTAssertEqual(dict["body"] as? String, "Body")
        XCTAssertEqual(dict["imageUrl"] as? String, "https://example.com/image.png")
    }

    func testInboxContent_encoding() throws {
        let content = InboxContent(title: "Test", body: "Body")

        let data = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(InboxContent.self, from: data)

        XCTAssertEqual(decoded.title, "Test")
        XCTAssertEqual(decoded.body, "Body")
    }

    // MARK: - InboxMessage Tests

    func testInboxMessage_initMinimal() {
        let content = InboxContent(title: "Title", body: "Body")
        let message = InboxMessage(
            id: "msg123",
            content: content,
            createdAt: "2024-01-15T10:00:00Z"
        )

        XCTAssertEqual(message.id, "msg123")
        XCTAssertEqual(message.content.title, "Title")
        XCTAssertEqual(message.status, .unread)
        XCTAssertNil(message.userId)
        XCTAssertNil(message.deviceId)
        XCTAssertNil(message.category)
    }

    func testInboxMessage_initFull() {
        let content = InboxContent(title: "Title", body: "Body")
        let message = InboxMessage(
            id: "msg123",
            userId: "user456",
            deviceId: "device789",
            content: content,
            status: .read,
            category: "promo",
            expiresAt: "2024-02-15T10:00:00Z",
            readAt: "2024-01-16T08:00:00Z",
            createdAt: "2024-01-15T10:00:00Z",
            updatedAt: "2024-01-16T08:00:00Z"
        )

        XCTAssertEqual(message.id, "msg123")
        XCTAssertEqual(message.userId, "user456")
        XCTAssertEqual(message.deviceId, "device789")
        XCTAssertEqual(message.status, .read)
        XCTAssertEqual(message.category, "promo")
        XCTAssertEqual(message.expiresAt, "2024-02-15T10:00:00Z")
        XCTAssertEqual(message.readAt, "2024-01-16T08:00:00Z")
    }

    func testInboxMessage_toDictionary() {
        let content = InboxContent(title: "Test", body: "Body")
        let message = InboxMessage(
            id: "msg123",
            userId: "user456",
            content: content,
            status: .read,
            category: "news",
            createdAt: "2024-01-15T10:00:00Z"
        )

        let dict = message.toDictionary()

        XCTAssertEqual(dict["id"] as? String, "msg123")
        XCTAssertEqual(dict["userId"] as? String, "user456")
        XCTAssertEqual(dict["status"] as? String, "read")
        XCTAssertEqual(dict["category"] as? String, "news")
        XCTAssertNotNil(dict["content"])
    }

    func testInboxMessage_decoding() throws {
        let json = """
        {
            "id": "msg123",
            "userId": "user456",
            "content": {
                "title": "Hello",
                "body": "World"
            },
            "status": "unread",
            "createdAt": "2024-01-15T10:00:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(InboxMessage.self, from: data)

        XCTAssertEqual(message.id, "msg123")
        XCTAssertEqual(message.userId, "user456")
        XCTAssertEqual(message.content.title, "Hello")
        XCTAssertEqual(message.content.body, "World")
        XCTAssertEqual(message.status, .unread)
    }

    // MARK: - InboxFilter Tests

    func testInboxFilter_defaultValues() {
        let filter = InboxFilter()

        XCTAssertNil(filter.userId)
        XCTAssertNil(filter.deviceId)
        XCTAssertNil(filter.status)
        XCTAssertNil(filter.category)
        XCTAssertEqual(filter.limit, 50)
        XCTAssertEqual(filter.offset, 0)
        XCTAssertNil(filter.locale)
    }

    func testInboxFilter_customValues() {
        let filter = InboxFilter(
            userId: "user123",
            status: .unread,
            category: "promo",
            limit: 20,
            offset: 10,
            locale: "en-US"
        )

        XCTAssertEqual(filter.userId, "user123")
        XCTAssertEqual(filter.status, .unread)
        XCTAssertEqual(filter.category, "promo")
        XCTAssertEqual(filter.limit, 20)
        XCTAssertEqual(filter.offset, 10)
        XCTAssertEqual(filter.locale, "en-US")
    }

    func testInboxFilter_toDictionary() {
        let filter = InboxFilter(
            status: .unread,
            category: "news",
            limit: 25,
            offset: 5
        )

        let dict = filter.toDictionary()

        XCTAssertEqual(dict["status"] as? String, "unread")
        XCTAssertEqual(dict["category"] as? String, "news")
        XCTAssertEqual(dict["limit"] as? Int, 25)
        XCTAssertEqual(dict["offset"] as? Int, 5)
    }

    // MARK: - InboxMessagesResponse Tests

    func testInboxMessagesResponse_init() {
        let content = InboxContent(title: "Test", body: "Body")
        let message = InboxMessage(id: "msg1", content: content, createdAt: "2024-01-15")

        let response = InboxMessagesResponse(
            messages: [message],
            total: 10,
            unreadCount: 5
        )

        XCTAssertEqual(response.messages.count, 1)
        XCTAssertEqual(response.total, 10)
        XCTAssertEqual(response.unreadCount, 5)
    }

    func testInboxMessagesResponse_decoding() throws {
        let json = """
        {
            "messages": [
                {
                    "id": "msg1",
                    "content": {"title": "Hello", "body": "World"},
                    "status": "unread",
                    "createdAt": "2024-01-15"
                },
                {
                    "id": "msg2",
                    "content": {"title": "Test", "body": "Message"},
                    "status": "read",
                    "createdAt": "2024-01-14"
                }
            ],
            "total": 100,
            "unreadCount": 42
        }
        """

        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(InboxMessagesResponse.self, from: data)

        XCTAssertEqual(response.messages.count, 2)
        XCTAssertEqual(response.messages[0].id, "msg1")
        XCTAssertEqual(response.messages[1].id, "msg2")
        XCTAssertEqual(response.total, 100)
        XCTAssertEqual(response.unreadCount, 42)
    }

    func testInboxMessagesResponse_toDictionary() {
        let content = InboxContent(title: "Test", body: "Body")
        let message = InboxMessage(id: "msg1", content: content, createdAt: "2024-01-15")

        let response = InboxMessagesResponse(
            messages: [message],
            total: 10,
            unreadCount: 5
        )

        let dict = response.toDictionary()

        XCTAssertEqual(dict["total"] as? Int, 10)
        XCTAssertEqual(dict["unreadCount"] as? Int, 5)
        XCTAssertNotNil(dict["messages"])
    }
}
