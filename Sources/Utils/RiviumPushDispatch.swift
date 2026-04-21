import Foundation

/// Centralized dispatch management for Rivium Push SDK.
/// Provides utility methods for thread-safe operations.
internal struct RiviumPushDispatch {

    /// Serial queue for IO operations (UserDefaults, file I/O)
    static let ioQueue = DispatchQueue(label: "co.rivium.push.sdk.io", qos: .utility)

    /// Serial queue for state synchronization
    static let stateQueue = DispatchQueue(label: "co.rivium.push.sdk.state", qos: .userInitiated)

    /// Execute a block on the IO queue (for UserDefaults, file operations)
    static func io(_ block: @escaping () -> Void) {
        ioQueue.async(execute: block)
    }

    /// Execute a block on the main queue
    static func main(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }

    /// Execute a block on the main queue after a delay
    static func mainAfter(seconds: Double, _ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: block)
    }

    /// Execute a block synchronously on the state queue (thread-safe read/write)
    static func stateSync<T>(_ block: () -> T) -> T {
        return stateQueue.sync(execute: block)
    }

    /// Execute a block asynchronously on the state queue
    static func stateAsync(_ block: @escaping () -> Void) {
        stateQueue.async(execute: block)
    }

    /// Execute a block on a background queue (for general background tasks)
    static func executeBackground(_ block: @escaping () -> Void) {
        DispatchQueue.global(qos: .background).async(execute: block)
    }
}
