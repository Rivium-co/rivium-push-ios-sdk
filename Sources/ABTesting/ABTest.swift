import Foundation

/// Represents an A/B test variant assignment
public struct ABTestVariant: Codable {
    public let testId: String
    public let variantId: String
    public let variantName: String
    public let isControlGroup: Bool
    public let content: ABTestContent?

    enum CodingKeys: String, CodingKey {
        case testId, variantId, variantName, isControlGroup, content
    }

    public init(testId: String, variantId: String, variantName: String, isControlGroup: Bool = false, content: ABTestContent?) {
        self.testId = testId
        self.variantId = variantId
        self.variantName = variantName
        self.isControlGroup = isControlGroup
        self.content = content
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        testId = try container.decode(String.self, forKey: .testId)
        variantId = try container.decode(String.self, forKey: .variantId)
        variantName = try container.decode(String.self, forKey: .variantName)
        isControlGroup = try container.decodeIfPresent(Bool.self, forKey: .isControlGroup) ?? false
        content = try container.decodeIfPresent(ABTestContent.self, forKey: .content)
    }

    /// Convert to dictionary for Flutter bridge
    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "testId": testId,
            "variantId": variantId,
            "variantName": variantName,
            "isControlGroup": isControlGroup
        ]
        if let content = content {
            dict["content"] = content.toDictionary()
        }
        return dict
    }
}

/// Content for an A/B test variant
public struct ABTestContent: Codable {
    public let title: String
    public let body: String
    public let data: [String: AnyCodable]?
    public let imageUrl: String?
    public let deepLink: String?
    public let actions: [ABTestAction]?

    public init(
        title: String,
        body: String,
        data: [String: AnyCodable]? = nil,
        imageUrl: String? = nil,
        deepLink: String? = nil,
        actions: [ABTestAction]? = nil
    ) {
        self.title = title
        self.body = body
        self.data = data
        self.imageUrl = imageUrl
        self.deepLink = deepLink
        self.actions = actions
    }

    /// Convert to dictionary for Flutter bridge
    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "title": title,
            "body": body
        ]
        if let imageUrl = imageUrl {
            dict["imageUrl"] = imageUrl
        }
        if let deepLink = deepLink {
            dict["deepLink"] = deepLink
        }
        if let data = data {
            dict["data"] = data.mapValues { $0.value }
        }
        if let actions = actions {
            dict["actions"] = actions.map { $0.toDictionary() }
        }
        return dict
    }
}

/// Action button for A/B test variant
public struct ABTestAction: Codable {
    public let id: String
    public let title: String
    public let action: String

    public init(id: String, title: String, action: String) {
        self.id = id
        self.title = title
        self.action = action
    }

    /// Convert to dictionary for Flutter bridge
    public func toDictionary() -> [String: Any] {
        return [
            "id": id,
            "title": title,
            "action": action
        ]
    }
}

/// Summary of an active A/B test
public struct ABTestSummary: Codable {
    public let id: String
    public let name: String
    public let variantCount: Int
    public let hasControlGroup: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, variantCount, hasControlGroup
    }

    public init(id: String, name: String, variantCount: Int, hasControlGroup: Bool = false) {
        self.id = id
        self.name = name
        self.variantCount = variantCount
        self.hasControlGroup = hasControlGroup
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        variantCount = try container.decodeIfPresent(Int.self, forKey: .variantCount) ?? 0
        hasControlGroup = try container.decodeIfPresent(Bool.self, forKey: .hasControlGroup) ?? false
    }

    /// Convert to dictionary for Flutter bridge
    public func toDictionary() -> [String: Any] {
        return [
            "id": id,
            "name": name,
            "variantCount": variantCount,
            "hasControlGroup": hasControlGroup
        ]
    }
}

/// Statistical results for an A/B test
public struct ABTestStatistics: Codable {
    public let isSignificant: Bool
    public let confidenceLevel: Double
    public let pValue: Double
    public let lift: Double
    public let sampleSizeRecommendation: Int?

    public init(
        isSignificant: Bool,
        confidenceLevel: Double,
        pValue: Double,
        lift: Double,
        sampleSizeRecommendation: Int? = nil
    ) {
        self.isSignificant = isSignificant
        self.confidenceLevel = confidenceLevel
        self.pValue = pValue
        self.lift = lift
        self.sampleSizeRecommendation = sampleSizeRecommendation
    }

    /// Convert to dictionary for Flutter bridge
    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "isSignificant": isSignificant,
            "confidenceLevel": confidenceLevel,
            "pValue": pValue,
            "lift": lift
        ]
        if let sampleSize = sampleSizeRecommendation {
            dict["sampleSizeRecommendation"] = sampleSize
        }
        return dict
    }
}

/// Confidence interval for a metric
public struct ConfidenceInterval: Codable {
    public let lower: Double
    public let upper: Double

    public init(lower: Double, upper: Double) {
        self.lower = lower
        self.upper = upper
    }

    /// Convert to dictionary for Flutter bridge
    public func toDictionary() -> [String: Any] {
        return [
            "lower": lower,
            "upper": upper
        ]
    }
}

/// Variant statistics with confidence intervals
public struct ABTestVariantStats: Codable {
    public let id: String
    public let name: String
    public let isControlGroup: Bool
    public let trafficPercentage: Int
    public let sentCount: Int
    public let deliveredCount: Int
    public let openedCount: Int
    public let clickedCount: Int
    public let convertedCount: Int
    public let failedCount: Int
    public let deliveryRate: Double
    public let openRate: Double
    public let clickRate: Double
    public let conversionRate: Double
    public let confidenceInterval: ConfidenceInterval?
    public let improvementVsControl: Double?
    public let isSignificantVsControl: Bool?
    public let pValueVsControl: Double?

    public init(
        id: String,
        name: String,
        isControlGroup: Bool,
        trafficPercentage: Int,
        sentCount: Int,
        deliveredCount: Int,
        openedCount: Int,
        clickedCount: Int,
        convertedCount: Int,
        failedCount: Int,
        deliveryRate: Double,
        openRate: Double,
        clickRate: Double,
        conversionRate: Double,
        confidenceInterval: ConfidenceInterval? = nil,
        improvementVsControl: Double? = nil,
        isSignificantVsControl: Bool? = nil,
        pValueVsControl: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.isControlGroup = isControlGroup
        self.trafficPercentage = trafficPercentage
        self.sentCount = sentCount
        self.deliveredCount = deliveredCount
        self.openedCount = openedCount
        self.clickedCount = clickedCount
        self.convertedCount = convertedCount
        self.failedCount = failedCount
        self.deliveryRate = deliveryRate
        self.openRate = openRate
        self.clickRate = clickRate
        self.conversionRate = conversionRate
        self.confidenceInterval = confidenceInterval
        self.improvementVsControl = improvementVsControl
        self.isSignificantVsControl = isSignificantVsControl
        self.pValueVsControl = pValueVsControl
    }

    /// Convert to dictionary for Flutter bridge
    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "name": name,
            "isControlGroup": isControlGroup,
            "trafficPercentage": trafficPercentage,
            "sentCount": sentCount,
            "deliveredCount": deliveredCount,
            "openedCount": openedCount,
            "clickedCount": clickedCount,
            "convertedCount": convertedCount,
            "failedCount": failedCount,
            "deliveryRate": deliveryRate,
            "openRate": openRate,
            "clickRate": clickRate,
            "conversionRate": conversionRate
        ]
        if let ci = confidenceInterval {
            dict["confidenceInterval"] = ci.toDictionary()
        }
        if let improvement = improvementVsControl {
            dict["improvementVsControl"] = improvement
        }
        if let significant = isSignificantVsControl {
            dict["isSignificantVsControl"] = significant
        }
        if let pValue = pValueVsControl {
            dict["pValueVsControl"] = pValue
        }
        return dict
    }
}

/// Tracking event types for A/B tests
public enum ABTestEvent: String {
    case impression = "impression"
    case opened = "opened"
    case clicked = "clicked"
    case converted = "converted"
}

/// Helper type for encoding/decoding Any values
public struct AnyCodable: Codable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}
