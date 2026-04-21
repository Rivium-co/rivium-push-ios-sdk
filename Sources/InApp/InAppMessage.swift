import Foundation

/// In-App Message types
public enum InAppMessageType: String, Codable {
    case modal = "modal"
    case banner = "banner"
    case fullscreen = "fullscreen"
    case card = "card"

    public static func fromString(_ value: String) -> InAppMessageType {
        return InAppMessageType(rawValue: value) ?? .modal
    }
}

/// In-App Message trigger types
public enum InAppTriggerType: String, Codable {
    case onAppOpen = "on_app_open"
    case onEvent = "on_event"
    case onSessionStart = "on_session_start"
    case scheduled = "scheduled"
    case manual = "manual"

    public static func fromString(_ value: String) -> InAppTriggerType {
        return InAppTriggerType(rawValue: value) ?? .onAppOpen
    }
}

/// Button style for in-app message buttons
public enum InAppButtonStyle: String, Codable {
    case primary = "primary"
    case secondary = "secondary"
    case text = "text"
    case destructive = "destructive"

    public static func fromString(_ value: String) -> InAppButtonStyle {
        return InAppButtonStyle(rawValue: value) ?? .primary
    }
}

/// Button action type
public enum InAppButtonAction: String, Codable {
    case dismiss = "dismiss"
    case deepLink = "deep_link"
    case url = "url"
    case custom = "custom"

    public static func fromString(_ value: String) -> InAppButtonAction {
        return InAppButtonAction(rawValue: value) ?? .dismiss
    }
}

/// In-App Message button
public struct InAppButton: Codable {
    public let id: String
    public let text: String
    public let action: InAppButtonAction
    public let value: String?
    public let style: InAppButtonStyle

    public init(
        id: String,
        text: String,
        action: InAppButtonAction = .dismiss,
        value: String? = nil,
        style: InAppButtonStyle = .primary
    ) {
        self.id = id
        self.text = text
        self.action = action
        self.value = value
        self.style = style
    }

    public static func fromJson(_ json: [String: Any]) -> InAppButton? {
        guard let id = json["id"] as? String,
              let text = json["text"] as? String else {
            return nil
        }

        return InAppButton(
            id: id,
            text: text,
            action: InAppButtonAction.fromString(json["action"] as? String ?? "dismiss"),
            value: json["value"] as? String,
            style: InAppButtonStyle.fromString(json["style"] as? String ?? "primary")
        )
    }

    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "text": text,
            "action": action.rawValue,
            "style": style.rawValue
        ]
        if let value = value {
            dict["value"] = value
        }
        return dict
    }
}

/// In-App Message content
public struct InAppMessageContent: Codable {
    public let title: String
    public let body: String
    public let imageUrl: String?
    public let backgroundColor: String?
    public let textColor: String?
    public let buttons: [InAppButton]

    public init(
        title: String,
        body: String,
        imageUrl: String? = nil,
        backgroundColor: String? = nil,
        textColor: String? = nil,
        buttons: [InAppButton] = []
    ) {
        self.title = title
        self.body = body
        self.imageUrl = imageUrl
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.buttons = buttons
    }

    public static func fromJson(_ json: [String: Any]) -> InAppMessageContent? {
        guard let title = json["title"] as? String,
              let body = json["body"] as? String else {
            return nil
        }

        var buttons: [InAppButton] = []
        if let buttonsArray = json["buttons"] as? [[String: Any]] {
            buttons = buttonsArray.compactMap { InAppButton.fromJson($0) }
        }

        return InAppMessageContent(
            title: title,
            body: body,
            imageUrl: json["imageUrl"] as? String,
            backgroundColor: json["backgroundColor"] as? String,
            textColor: json["textColor"] as? String,
            buttons: buttons
        )
    }

    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "title": title,
            "body": body,
            "buttons": buttons.map { $0.toDictionary() }
        ]
        if let imageUrl = imageUrl { dict["imageUrl"] = imageUrl }
        if let backgroundColor = backgroundColor { dict["backgroundColor"] = backgroundColor }
        if let textColor = textColor { dict["textColor"] = textColor }
        return dict
    }
}

/// Localized content for in-app messages
public struct InAppLocalizedContent: Codable {
    public let locale: String
    public let content: InAppMessageContent

    public init(locale: String, content: InAppMessageContent) {
        self.locale = locale
        self.content = content
    }

    public static func fromJson(_ json: [String: Any]) -> InAppLocalizedContent? {
        guard let locale = json["locale"] as? String,
              let contentJson = json["content"] as? [String: Any],
              let content = InAppMessageContent.fromJson(contentJson) else {
            return nil
        }
        return InAppLocalizedContent(locale: locale, content: content)
    }
}

/// In-App Message
public struct InAppMessage: Codable {
    public let id: String
    public let name: String
    public let type: InAppMessageType
    public let content: InAppMessageContent
    public let localizations: [InAppLocalizedContent]
    public let triggerType: InAppTriggerType
    public let triggerEvent: String?
    public let triggerConditions: [String: Any]?
    public let startDate: TimeInterval?
    public let endDate: TimeInterval?
    public let maxImpressions: Int
    public let minSessionCount: Int
    public let delaySeconds: Int
    public let priority: Int

    enum CodingKeys: String, CodingKey {
        case id, name, type, content, localizations, triggerType, triggerEvent
        case startDate, endDate, maxImpressions, minSessionCount, delaySeconds, priority
    }

    public init(
        id: String,
        name: String,
        type: InAppMessageType,
        content: InAppMessageContent,
        localizations: [InAppLocalizedContent] = [],
        triggerType: InAppTriggerType,
        triggerEvent: String? = nil,
        triggerConditions: [String: Any]? = nil,
        startDate: TimeInterval? = nil,
        endDate: TimeInterval? = nil,
        maxImpressions: Int = 1,
        minSessionCount: Int = 0,
        delaySeconds: Int = 0,
        priority: Int = 0
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.content = content
        self.localizations = localizations
        self.triggerType = triggerType
        self.triggerEvent = triggerEvent
        self.triggerConditions = triggerConditions
        self.startDate = startDate
        self.endDate = endDate
        self.maxImpressions = maxImpressions
        self.minSessionCount = minSessionCount
        self.delaySeconds = delaySeconds
        self.priority = priority
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        type = try container.decodeIfPresent(InAppMessageType.self, forKey: .type) ?? .modal
        content = try container.decode(InAppMessageContent.self, forKey: .content)
        localizations = try container.decodeIfPresent([InAppLocalizedContent].self, forKey: .localizations) ?? []
        triggerType = try container.decodeIfPresent(InAppTriggerType.self, forKey: .triggerType) ?? .onAppOpen
        triggerEvent = try container.decodeIfPresent(String.self, forKey: .triggerEvent)
        triggerConditions = nil
        startDate = try container.decodeIfPresent(TimeInterval.self, forKey: .startDate)
        endDate = try container.decodeIfPresent(TimeInterval.self, forKey: .endDate)
        maxImpressions = try container.decodeIfPresent(Int.self, forKey: .maxImpressions) ?? 1
        minSessionCount = try container.decodeIfPresent(Int.self, forKey: .minSessionCount) ?? 0
        delaySeconds = try container.decodeIfPresent(Int.self, forKey: .delaySeconds) ?? 0
        priority = try container.decodeIfPresent(Int.self, forKey: .priority) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encode(content, forKey: .content)
        try container.encode(localizations, forKey: .localizations)
        try container.encode(triggerType, forKey: .triggerType)
        try container.encodeIfPresent(triggerEvent, forKey: .triggerEvent)
        try container.encodeIfPresent(startDate, forKey: .startDate)
        try container.encodeIfPresent(endDate, forKey: .endDate)
        try container.encode(maxImpressions, forKey: .maxImpressions)
        try container.encode(minSessionCount, forKey: .minSessionCount)
        try container.encode(delaySeconds, forKey: .delaySeconds)
        try container.encode(priority, forKey: .priority)
    }

    /// Parse from JSON dictionary
    public static func fromJson(_ json: [String: Any]) -> InAppMessage? {
        guard let id = json["id"] as? String,
              let contentJson = json["content"] as? [String: Any],
              let content = InAppMessageContent.fromJson(contentJson) else {
            return nil
        }

        var localizations: [InAppLocalizedContent] = []
        if let locArray = json["localizations"] as? [[String: Any]] {
            localizations = locArray.compactMap { InAppLocalizedContent.fromJson($0) }
        }

        // Parse dates (can be ISO 8601 string or epoch milliseconds)
        var startDate: TimeInterval? = nil
        var endDate: TimeInterval? = nil

        if let startMs = json["startDate"] as? Double {
            startDate = startMs / 1000.0
        } else if let startStr = json["startDate"] as? String {
            startDate = parseISODate(startStr)
        }

        if let endMs = json["endDate"] as? Double {
            endDate = endMs / 1000.0
        } else if let endStr = json["endDate"] as? String {
            endDate = parseISODate(endStr)
        }

        return InAppMessage(
            id: id,
            name: json["name"] as? String ?? "",
            type: InAppMessageType.fromString(json["type"] as? String ?? "modal"),
            content: content,
            localizations: localizations,
            triggerType: InAppTriggerType.fromString(json["triggerType"] as? String ?? "on_app_open"),
            triggerEvent: json["triggerEvent"] as? String,
            triggerConditions: json["triggerConditions"] as? [String: Any],
            startDate: startDate,
            endDate: endDate,
            maxImpressions: json["maxImpressions"] as? Int ?? 1,
            minSessionCount: json["minSessionCount"] as? Int ?? 0,
            delaySeconds: json["delaySeconds"] as? Int ?? 0,
            priority: json["priority"] as? Int ?? 0
        )
    }

    private static func parseISODate(_ dateString: String) -> TimeInterval? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            return date.timeIntervalSince1970
        }

        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: dateString) {
            return date.timeIntervalSince1970
        }

        return nil
    }

    /// Get localized content for the device's locale
    public func getLocalizedContent() -> InAppMessageContent {
        let locale = Locale.current.identifier.lowercased()
        let languageCode = Locale.current.languageCode?.lowercased() ?? "en"

        // Try exact match first
        if let exact = localizations.first(where: { $0.locale.lowercased() == locale }) {
            return exact.content
        }

        // Try language match
        if let lang = localizations.first(where: { $0.locale.lowercased().hasPrefix(languageCode) }) {
            return lang.content
        }

        // Fall back to default content
        return content
    }

    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "name": name,
            "type": type.rawValue,
            "content": content.toDictionary(),
            "triggerType": triggerType.rawValue,
            "maxImpressions": maxImpressions,
            "minSessionCount": minSessionCount,
            "delaySeconds": delaySeconds,
            "priority": priority
        ]

        if let triggerEvent = triggerEvent { dict["triggerEvent"] = triggerEvent }
        if let startDate = startDate { dict["startDate"] = startDate * 1000 } // Convert to ms
        if let endDate = endDate { dict["endDate"] = endDate * 1000 }

        return dict
    }
}

/// Impression action types
public enum InAppImpressionAction: String {
    case impression = "impression"
    case click = "click"
    case dismiss = "dismiss"
    case buttonClick = "button_click"

    public static func fromString(_ value: String) -> InAppImpressionAction {
        return InAppImpressionAction(rawValue: value) ?? .impression
    }
}

/// Callback interface for in-app message events
public protocol InAppMessageCallback: AnyObject {
    /// Called when an in-app message is ready to be displayed
    func inAppMessageReady(_ message: InAppMessage)

    /// Called when a button is clicked
    func inAppMessageButtonClicked(_ message: InAppMessage, button: InAppButton)

    /// Called when the message is dismissed
    func inAppMessageDismissed(_ message: InAppMessage)

    /// Called when there's an error
    func inAppMessageError(_ error: String)
}

/// Default implementations
public extension InAppMessageCallback {
    func inAppMessageReady(_ message: InAppMessage) {}
    func inAppMessageButtonClicked(_ message: InAppMessage, button: InAppButton) {}
    func inAppMessageDismissed(_ message: InAppMessage) {}
    func inAppMessageError(_ error: String) {}
}
