import Foundation
import os.log

/// Log levels for the Rivium Push SDK
public enum RiviumPushLogLevel: Int, Comparable {
    /// No logging at all (for production)
    case none = 0
    /// Only errors
    case error = 1
    /// Errors and warnings
    case warning = 2
    /// Errors, warnings, and info messages
    case info = 3
    /// All messages including debug output (default for development)
    case debug = 4
    /// Everything including very detailed traces
    case verbose = 5

    public static func < (lhs: RiviumPushLogLevel, rhs: RiviumPushLogLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }

    public static func fromString(_ level: String) -> RiviumPushLogLevel {
        switch level.lowercased() {
        case "none": return .none
        case "error": return .error
        case "warning": return .warning
        case "info": return .info
        case "debug": return .debug
        case "verbose": return .verbose
        default: return .debug
        }
    }

    public var name: String {
        switch self {
        case .none: return "none"
        case .error: return "error"
        case .warning: return "warning"
        case .info: return "info"
        case .debug: return "debug"
        case .verbose: return "verbose"
        }
    }
}

/// Logger for Rivium Push SDK with configurable log levels
public class RiviumPushLogger {
    public static var logLevel: RiviumPushLogLevel = .debug

    private static let subsystem = "co.rivium.push.sdk"

    public static func setLogLevel(fromString level: String) {
        logLevel = RiviumPushLogLevel.fromString(level)
    }

    public static func v(_ tag: String, _ message: String) {
        guard logLevel >= .verbose else { return }
        log(tag, message, level: .verbose)
    }

    public static func d(_ tag: String, _ message: String) {
        guard logLevel >= .debug else { return }
        log(tag, message, level: .debug)
    }

    public static func i(_ tag: String, _ message: String) {
        guard logLevel >= .info else { return }
        log(tag, message, level: .info)
    }

    public static func w(_ tag: String, _ message: String) {
        guard logLevel >= .warning else { return }
        log(tag, message, level: .warning)
    }

    public static func e(_ tag: String, _ message: String, error: Error? = nil) {
        guard logLevel >= .error else { return }
        var fullMessage = message
        if let error = error {
            fullMessage += " - \(error.localizedDescription)"
        }
        log(tag, fullMessage, level: .error)
    }

    private static func log(_ tag: String, _ message: String, level: RiviumPushLogLevel) {
        let osLogType: OSLogType
        switch level {
        case .none: return
        case .error: osLogType = .error
        case .warning: osLogType = .fault
        case .info: osLogType = .info
        case .debug: osLogType = .debug
        case .verbose: osLogType = .debug
        }

        let logger = OSLog(subsystem: subsystem, category: tag)
        os_log("%{public}@", log: logger, type: osLogType, "RiviumPush.\(tag): \(message)")

        // Also print to console in debug builds
        #if DEBUG
        let prefix: String
        switch level {
        case .none: prefix = ""
        case .error: prefix = "🔴"
        case .warning: prefix = "🟠"
        case .info: prefix = "🔵"
        case .debug: prefix = "🟢"
        case .verbose: prefix = "⚪"
        }
        print("\(prefix) RiviumPush.\(tag): \(message)")
        #endif
    }
}

/// Convenience typealias for shorter logging calls
public typealias Log = RiviumPushLogger
