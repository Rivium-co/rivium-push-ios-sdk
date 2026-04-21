import Foundation

/// Action button for notifications
public struct NotificationAction: Codable {
    public let id: String
    public let title: String
    public let action: String?
    public let icon: String?
    public let destructive: Bool
    public let authRequired: Bool

    public init(
        id: String,
        title: String,
        action: String? = nil,
        icon: String? = nil,
        destructive: Bool = false,
        authRequired: Bool = false
    ) {
        self.id = id
        self.title = title
        self.action = action
        self.icon = icon
        self.destructive = destructive
        self.authRequired = authRequired
    }

    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "title": title,
            "destructive": destructive,
            "authRequired": authRequired
        ]
        if let action = action { dict["action"] = action }
        if let icon = icon { dict["icon"] = icon }
        return dict
    }
}

/// Localized content for notifications
public struct LocalizedContent: Codable {
    public let locale: String
    public let title: String
    public let body: String

    public init(locale: String, title: String, body: String) {
        self.locale = locale
        self.title = title
        self.body = body
    }

    public func toDictionary() -> [String: Any] {
        return [
            "locale": locale,
            "title": title,
            "body": body
        ]
    }
}

/// Push notification message with rich notification support
public struct RiviumPushMessage: Codable {
    // Core fields
    public let title: String
    public let body: String
    public let data: [String: RiviumPushAnyCodable]?
    public let silent: Bool

    // Rich notification fields
    public let imageUrl: String?
    public let iconUrl: String?
    public let actions: [NotificationAction]?
    public let deepLink: String?

    // Badge
    public let badge: Int?
    public let badgeAction: String?

    // Sound & grouping
    public let sound: String?
    public let threadId: String?
    public let collapseKey: String?
    public let category: String?

    // Priority & TTL
    public let priority: String?
    public let ttl: Int?

    // Localization
    public let localizations: [LocalizedContent]?
    public let timezone: String?

    // Analytics
    public let messageId: String?
    public let campaignId: String?

    public init(
        title: String,
        body: String,
        data: [String: RiviumPushAnyCodable]? = nil,
        silent: Bool = false,
        imageUrl: String? = nil,
        iconUrl: String? = nil,
        actions: [NotificationAction]? = nil,
        deepLink: String? = nil,
        badge: Int? = nil,
        badgeAction: String? = nil,
        sound: String? = nil,
        threadId: String? = nil,
        collapseKey: String? = nil,
        category: String? = nil,
        priority: String? = nil,
        ttl: Int? = nil,
        localizations: [LocalizedContent]? = nil,
        timezone: String? = nil,
        messageId: String? = nil,
        campaignId: String? = nil
    ) {
        self.title = title
        self.body = body
        self.data = data
        self.silent = silent
        self.imageUrl = imageUrl
        self.iconUrl = iconUrl
        self.actions = actions
        self.deepLink = deepLink
        self.badge = badge
        self.badgeAction = badgeAction
        self.sound = sound
        self.threadId = threadId
        self.collapseKey = collapseKey
        self.category = category
        self.priority = priority
        self.ttl = ttl
        self.localizations = localizations
        self.timezone = timezone
        self.messageId = messageId
        self.campaignId = campaignId
    }

    /// Parse message from JSON string
    public static func from(json: String) -> RiviumPushMessage? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(RiviumPushMessage.self, from: data)
    }

    /// Parse message from dictionary (VoIP payload or notification userInfo)
    public static func from(payload: [AnyHashable: Any]) -> RiviumPushMessage? {
        guard let title = payload["title"] as? String,
              let body = payload["body"] as? String else {
            return nil
        }

        // Parse data
        var dataDict: [String: RiviumPushAnyCodable]? = nil
        if let payloadData = payload["data"] as? [String: Any] {
            dataDict = payloadData.mapValues { RiviumPushAnyCodable($0) }
        }

        // Parse actions
        var actions: [NotificationAction]? = nil
        if let actionsArray = payload["actions"] as? [[String: Any]] {
            actions = actionsArray.compactMap { actionDict -> NotificationAction? in
                guard let id = actionDict["id"] as? String,
                      let title = actionDict["title"] as? String else { return nil }
                return NotificationAction(
                    id: id,
                    title: title,
                    action: actionDict["action"] as? String,
                    icon: actionDict["icon"] as? String,
                    destructive: actionDict["destructive"] as? Bool ?? false,
                    authRequired: actionDict["authRequired"] as? Bool ?? false
                )
            }
        }

        // Parse localizations
        var localizations: [LocalizedContent]? = nil
        if let locArray = payload["localizations"] as? [[String: Any]] {
            localizations = locArray.compactMap { locDict -> LocalizedContent? in
                guard let locale = locDict["locale"] as? String,
                      let title = locDict["title"] as? String,
                      let body = locDict["body"] as? String else { return nil }
                return LocalizedContent(locale: locale, title: title, body: body)
            }
        }

        return RiviumPushMessage(
            title: title,
            body: body,
            data: dataDict,
            silent: payload["silent"] as? Bool ?? false,
            imageUrl: payload["imageUrl"] as? String,
            iconUrl: payload["iconUrl"] as? String,
            actions: actions,
            deepLink: payload["deepLink"] as? String,
            badge: payload["badge"] as? Int,
            badgeAction: payload["badgeAction"] as? String,
            sound: payload["sound"] as? String,
            threadId: payload["threadId"] as? String,
            collapseKey: payload["collapseKey"] as? String,
            category: payload["category"] as? String,
            priority: payload["priority"] as? String,
            ttl: payload["ttl"] as? Int,
            localizations: localizations,
            timezone: payload["timezone"] as? String,
            messageId: payload["messageId"] as? String,
            campaignId: payload["campaignId"] as? String
        )
    }

    /// Convert to JSON string
    public func toJson() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Convert to dictionary for bridging
    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "title": title,
            "body": body,
            "silent": silent
        ]

        if let data = data {
            dict["data"] = data.mapValues { $0.value }
        }
        if let imageUrl = imageUrl { dict["imageUrl"] = imageUrl }
        if let iconUrl = iconUrl { dict["iconUrl"] = iconUrl }
        if let actions = actions { dict["actions"] = actions.map { $0.toDictionary() } }
        if let deepLink = deepLink { dict["deepLink"] = deepLink }
        if let badge = badge { dict["badge"] = badge }
        if let badgeAction = badgeAction { dict["badgeAction"] = badgeAction }
        if let sound = sound { dict["sound"] = sound }
        if let threadId = threadId { dict["threadId"] = threadId }
        if let collapseKey = collapseKey { dict["collapseKey"] = collapseKey }
        if let category = category { dict["category"] = category }
        if let priority = priority { dict["priority"] = priority }
        if let ttl = ttl { dict["ttl"] = ttl }
        if let localizations = localizations { dict["localizations"] = localizations.map { $0.toDictionary() } }
        if let timezone = timezone { dict["timezone"] = timezone }
        if let messageId = messageId { dict["messageId"] = messageId }
        if let campaignId = campaignId { dict["campaignId"] = campaignId }

        return dict
    }

    /// Get the localized title for the given locale, or the default title
    public func getLocalizedTitle(locale: String) -> String {
        return localizations?.first { $0.locale == locale }?.title ?? title
    }

    /// Get the localized body for the given locale, or the default body
    public func getLocalizedBody(locale: String) -> String {
        return localizations?.first { $0.locale == locale }?.body ?? body
    }

    /// Get localized title for device's current locale
    public func getLocalizedTitle() -> String {
        let locale = Locale.current.identifier
        let languageCode = Locale.current.languageCode ?? "en"

        // Try exact match first
        if let exact = localizations?.first(where: { $0.locale.lowercased() == locale.lowercased() }) {
            return exact.title
        }

        // Try language match
        if let lang = localizations?.first(where: { $0.locale.lowercased().hasPrefix(languageCode.lowercased()) }) {
            return lang.title
        }

        return title
    }

    /// Get localized body for device's current locale
    public func getLocalizedBody() -> String {
        let locale = Locale.current.identifier
        let languageCode = Locale.current.languageCode ?? "en"

        // Try exact match first
        if let exact = localizations?.first(where: { $0.locale.lowercased() == locale.lowercased() }) {
            return exact.body
        }

        // Try language match
        if let lang = localizations?.first(where: { $0.locale.lowercased().hasPrefix(languageCode.lowercased()) }) {
            return lang.body
        }

        return body
    }

    // Custom decoder to handle missing optional fields with defaults
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        data = try container.decodeIfPresent([String: RiviumPushAnyCodable].self, forKey: .data)
        silent = try container.decodeIfPresent(Bool.self, forKey: .silent) ?? false

        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        iconUrl = try container.decodeIfPresent(String.self, forKey: .iconUrl)
        actions = try container.decodeIfPresent([NotificationAction].self, forKey: .actions)
        deepLink = try container.decodeIfPresent(String.self, forKey: .deepLink)

        badge = try container.decodeIfPresent(Int.self, forKey: .badge)
        badgeAction = try container.decodeIfPresent(String.self, forKey: .badgeAction)

        sound = try container.decodeIfPresent(String.self, forKey: .sound)
        threadId = try container.decodeIfPresent(String.self, forKey: .threadId)
        collapseKey = try container.decodeIfPresent(String.self, forKey: .collapseKey)
        category = try container.decodeIfPresent(String.self, forKey: .category)

        priority = try container.decodeIfPresent(String.self, forKey: .priority)
        ttl = try container.decodeIfPresent(Int.self, forKey: .ttl)

        localizations = try container.decodeIfPresent([LocalizedContent].self, forKey: .localizations)
        timezone = try container.decodeIfPresent(String.self, forKey: .timezone)

        messageId = try container.decodeIfPresent(String.self, forKey: .messageId)
        campaignId = try container.decodeIfPresent(String.self, forKey: .campaignId)
    }

    private enum CodingKeys: String, CodingKey {
        case title, body, data, silent
        case imageUrl, iconUrl, actions, deepLink
        case badge, badgeAction
        case sound, threadId, collapseKey, category
        case priority, ttl
        case localizations, timezone
        case messageId, campaignId
    }
}

/// Type-erased Codable wrapper for dynamic JSON values
public struct RiviumPushAnyCodable: Codable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        // Try single value container for primitives
        if let container = try? decoder.singleValueContainer() {
            if let int = try? container.decode(Int.self) {
                value = int
                return
            } else if let double = try? container.decode(Double.self) {
                value = double
                return
            } else if let bool = try? container.decode(Bool.self) {
                value = bool
                return
            } else if let string = try? container.decode(String.self) {
                value = string
                return
            } else if container.decodeNil() {
                value = NSNull()
                return
            }
        }

        // Try unkeyed container for arrays
        if var unkeyedContainer = try? decoder.unkeyedContainer() {
            var array: [Any] = []
            while !unkeyedContainer.isAtEnd {
                if let item = try? unkeyedContainer.decode(RiviumPushAnyCodable.self) {
                    array.append(item.value)
                }
            }
            value = array
            return
        }

        // Try keyed container for dictionaries
        if let keyedContainer = try? decoder.container(keyedBy: DynamicCodingKey.self) {
            var dict: [String: Any] = [:]
            for key in keyedContainer.allKeys {
                if let item = try? keyedContainer.decode(RiviumPushAnyCodable.self, forKey: key) {
                    dict[key.stringValue] = item.value
                }
            }
            value = dict
            return
        }

        value = NSNull()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let bool as Bool:
            try container.encode(bool)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { RiviumPushAnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { RiviumPushAnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}

/// Dynamic coding key for decoding arbitrary JSON keys
private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
