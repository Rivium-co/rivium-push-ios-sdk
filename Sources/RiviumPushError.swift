import Foundation

/// Standardized error codes for Rivium Push SDK
public enum RiviumPushErrorCode: Int {
    // Connection errors (1000-1099)
    case connectionFailed = 1000
    case connectionTimeout = 1001
    case connectionLost = 1002
    case connectionRefused = 1003
    case authenticationFailed = 1004
    case sslError = 1005
    case brokerUnavailable = 1006

    // Subscription errors (1100-1199)
    case subscriptionFailed = 1100
    case unsubscriptionFailed = 1101
    case invalidTopic = 1102

    // Message errors (1200-1299)
    case messageDeliveryFailed = 1200
    case messageParseError = 1201
    case messageTimeout = 1202

    // Configuration errors (1300-1399)
    case invalidConfig = 1300
    case missingApiKey = 1301
    case missingServerUrl = 1302
    case invalidCredentials = 1303

    // Registration errors (1400-1499)
    case registrationFailed = 1400
    case deviceIdGenerationFailed = 1401
    case serverError = 1402
    case networkError = 1403

    // State errors (1500-1599)
    case notInitialized = 1500
    case notConnected = 1501
    case alreadyConnected = 1502
    case serviceNotRunning = 1503

    // A/B Testing errors (1600-1699)
    case variantNotFound = 1600
    case testNotFound = 1601

    // Unknown error
    case unknownError = 9999

    public var message: String {
        switch self {
        case .connectionFailed: return "Failed to connect to PN Protocol gateway"
        case .connectionTimeout: return "Connection timed out"
        case .connectionLost: return "Connection to server was lost"
        case .connectionRefused: return "Connection was refused by server"
        case .authenticationFailed: return "Authentication failed - invalid credentials"
        case .sslError: return "SSL/TLS handshake failed"
        case .brokerUnavailable: return "PN Protocol gateway is unavailable"
        case .subscriptionFailed: return "Failed to subscribe to topic"
        case .unsubscriptionFailed: return "Failed to unsubscribe from topic"
        case .invalidTopic: return "Invalid topic format"
        case .messageDeliveryFailed: return "Failed to deliver message"
        case .messageParseError: return "Failed to parse message payload"
        case .messageTimeout: return "Message delivery timed out"
        case .invalidConfig: return "Invalid configuration"
        case .missingApiKey: return "API key is missing"
        case .missingServerUrl: return "Server URL is missing"
        case .invalidCredentials: return "Invalid PN Protocol credentials"
        case .registrationFailed: return "Device registration failed"
        case .deviceIdGenerationFailed: return "Failed to generate device ID"
        case .serverError: return "Server returned an error"
        case .networkError: return "Network request failed"
        case .notInitialized: return "SDK is not initialized"
        case .notConnected: return "Not connected to server"
        case .alreadyConnected: return "Already connected to server"
        case .serviceNotRunning: return "Background service is not running"
        case .variantNotFound: return "A/B test variant not found"
        case .testNotFound: return "A/B test not found"
        case .unknownError: return "An unknown error occurred"
        }
    }

    public static func fromCode(_ code: Int) -> RiviumPushErrorCode {
        return RiviumPushErrorCode(rawValue: code) ?? .unknownError
    }

    public static func fromMqttError(_ error: Error) -> RiviumPushErrorCode {
        let message = error.localizedDescription.lowercased()

        if message.contains("connection refused") {
            return .connectionRefused
        } else if message.contains("connection lost") {
            return .connectionLost
        } else if message.contains("timed out") || message.contains("timeout") {
            return .connectionTimeout
        } else if message.contains("not authorized") || message.contains("bad user name or password") {
            return .authenticationFailed
        } else if message.contains("ssl") || message.contains("tls") {
            return .sslError
        } else if message.contains("unable to connect") || message.contains("server unavailable") {
            return .brokerUnavailable
        }

        return .connectionFailed
    }
}

/// Represents a RiviumPush error with code and additional details
public struct RiviumPushError: LocalizedError {
    public let errorCode: RiviumPushErrorCode
    public let details: String?
    public let cause: Error?

    public var code: Int { errorCode.rawValue }
    public var message: String { errorCode.message }

    public init(errorCode: RiviumPushErrorCode, details: String? = nil, cause: Error? = nil) {
        self.errorCode = errorCode
        self.details = details
        self.cause = cause
    }

    public var errorDescription: String? {
        if let details = details {
            return "\(message): \(details)"
        }
        return message
    }

    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "code": code,
            "message": message,
            "errorName": String(describing: errorCode)
        ]

        if let details = details ?? cause?.localizedDescription {
            dict["details"] = details
        }

        return dict
    }

    public static func fromException(_ error: Error, details: String? = nil) -> RiviumPushError {
        return RiviumPushError(
            errorCode: RiviumPushErrorCode.fromMqttError(error),
            details: details,
            cause: error
        )
    }

    // Common errors as static properties for convenience
    public static let notInitialized = RiviumPushError(errorCode: .notInitialized)
    public static let invalidUrl = RiviumPushError(errorCode: .invalidConfig, details: "Invalid server URL")
    public static let invalidResponse = RiviumPushError(errorCode: .serverError, details: "Invalid server response")
    public static let variantNotFound = RiviumPushError(errorCode: .variantNotFound)

    public static func serverError(_ statusCode: Int) -> RiviumPushError {
        return RiviumPushError(errorCode: .serverError, details: "HTTP status code: \(statusCode)")
    }

    public static func registrationFailed(_ message: String) -> RiviumPushError {
        return RiviumPushError(errorCode: .registrationFailed, details: message)
    }
}
