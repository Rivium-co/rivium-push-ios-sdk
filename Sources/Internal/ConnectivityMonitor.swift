import Foundation
import Network

/// Watches the network path and reports when a connection is worth retrying
/// right away: the network came back, or it moved to another interface
/// (Wi-Fi <-> cellular), which usually kills the old socket.
internal final class ConnectivityMonitor {
    /// Called on the main queue. `interfaceChanged` is true when the path moved
    /// to a different interface while it stayed usable.
    var onChange: ((_ kind: NetworkKind, _ interfaceChanged: Bool) -> Void)?

    /// Current network type (main queue).
    private(set) var currentKind: NetworkKind = .other

    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "co.rivium.push.connectivity")
    private var lastSatisfied: Bool?
    private var lastInterfaces: [String] = []

    var isRunning: Bool { monitor != nil }

    func start() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            let kind = ConnectivityMonitor.kind(of: path)
            let interfaces = path.availableInterfaces.map { $0.name }
            DispatchQueue.main.async {
                self?.handle(satisfied: satisfied, kind: kind, interfaces: interfaces)
            }
        }
        self.monitor = monitor
        monitor.start(queue: queue)
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
        lastSatisfied = nil
        lastInterfaces = []
    }

    private func handle(satisfied: Bool, kind: NetworkKind, interfaces: [String]) {
        guard monitor != nil else { return }
        let previousSatisfied = lastSatisfied
        let previousInterfaces = lastInterfaces
        lastSatisfied = satisfied
        lastInterfaces = interfaces
        currentKind = kind

        // First report is the baseline, not a change.
        guard let wasSatisfied = previousSatisfied, satisfied else { return }

        if !wasSatisfied {
            onChange?(kind, false)
        } else if interfaces.first != previousInterfaces.first {
            onChange?(kind, true)
        }
    }

    static func kind(of path: NWPath) -> NetworkKind {
        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.usesInterfaceType(.cellular) { return .cellular }
        return .other
    }
}
