import Foundation

/// Status of an inbox message
public enum InboxMessageStatus: String, Codable {
    case unread = "unread"
    case read = "read"
    case archived = "archived"
    case deleted = "deleted"

    public static func fromString(_ value: String) -> InboxMessageStatus {
        return InboxMessageStatus(rawValue: value.lowercased()) ?? .unread
    }
}

/// Content of an inbox message
public struct InboxContent: Codable {
    public let title: String
    public let body: String
    public let imageUrl: String?
    public let iconUrl: String?
    public let deepLink: String?
    public let data: [String: AnyCodable]?

    public init(
        title: String,
        body: String,
        imageUrl: String? = nil,
        iconUrl: String? = nil,
        deepLink: String? = nil,
        data: [String: AnyCodable]? = nil
    ) {
        self.title = title
        self.body = body
        self.imageUrl = imageUrl
        self.iconUrl = iconUrl
        self.deepLink = deepLink
        self.data = data
    }

    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "title": title,
            "body": body
        ]
        if let imageUrl = imageUrl { dict["imageUrl"] = imageUrl }
        if let iconUrl = iconUrl { dict["iconUrl"] = iconUrl }
        if let deepLink = deepLink { dict["deepLink"] = deepLink }
        if let data = data { dict["data"] = data.mapValues { $0.value } }
        return dict
    }
}

/// Represents an inbox message
public struct InboxMessage: Codable {
    public let id: String
    public let userId: String?
    public let deviceId: String?
    public let content: InboxContent
    public var status: InboxMessageStatus
    public let category: String?
    public let expiresAt: String?
    public let readAt: String?
    public let createdAt: String
    public let updatedAt: String?

    public init(
        id: String,
        userId: String? = nil,
        deviceId: String? = nil,
        content: InboxContent,
        status: InboxMessageStatus = .unread,
        category: String? = nil,
        expiresAt: String? = nil,
        readAt: String? = nil,
        createdAt: String,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.deviceId = deviceId
        self.content = content
        self.status = status
        self.category = category
        self.expiresAt = expiresAt
        self.readAt = readAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "content": content.toDictionary(),
            "status": status.rawValue,
            "createdAt": createdAt
        ]
        if let userId = userId { dict["userId"] = userId }
        if let deviceId = deviceId { dict["deviceId"] = deviceId }
        if let category = category { dict["category"] = category }
        if let expiresAt = expiresAt { dict["expiresAt"] = expiresAt }
        if let readAt = readAt { dict["readAt"] = readAt }
        if let updatedAt = updatedAt { dict["updatedAt"] = updatedAt }
        return dict
    }
}

/// Filter options for fetching inbox messages
public struct InboxFilter {
    public let userId: String?
    public let deviceId: String?
    public let status: InboxMessageStatus?
    public let category: String?
    public let limit: Int
    public let offset: Int
    public let locale: String?

    public init(
        userId: String? = nil,
        deviceId: String? = nil,
        status: InboxMessageStatus? = nil,
        category: String? = nil,
        limit: Int = 50,
        offset: Int = 0,
        locale: String? = nil
    ) {
        self.userId = userId
        self.deviceId = deviceId
        self.status = status
        self.category = category
        self.limit = limit
        self.offset = offset
        self.locale = locale
    }

    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "limit": limit,
            "offset": offset
        ]
        if let userId = userId { dict["userId"] = userId }
        if let deviceId = deviceId { dict["deviceId"] = deviceId }
        if let status = status { dict["status"] = status.rawValue }
        if let category = category { dict["category"] = category }
        if let locale = locale { dict["locale"] = locale }
        return dict
    }
}

/// Response from getInboxMessages API
public struct InboxMessagesResponse: Codable {
    public let messages: [InboxMessage]
    public let total: Int
    public let unreadCount: Int

    public init(messages: [InboxMessage], total: Int, unreadCount: Int) {
        self.messages = messages
        self.total = total
        self.unreadCount = unreadCount
    }

    public func toDictionary() -> [String: Any] {
        return [
            "messages": messages.map { $0.toDictionary() },
            "total": total,
            "unreadCount": unreadCount
        ]
    }
}

/// Callback interface for inbox operations
public protocol InboxCallback: AnyObject {
    /// Called when a new inbox message is received
    func inboxMessageReceived(_ message: InboxMessage)

    /// Called when inbox message status changes
    func inboxMessageStatusChanged(messageId: String, status: InboxMessageStatus)
}

/// Default implementations
public extension InboxCallback {
    func inboxMessageReceived(_ message: InboxMessage) {}
    func inboxMessageStatusChanged(messageId: String, status: InboxMessageStatus) {}
}
