import Foundation
import PNProtocol

/// Manager that wraps PNSocket for the Rivium Push SDK.
/// Replaces the old MqttManager with the new PN Protocol.
internal class PNSocketManager: NSObject {
    private var socket: PNSocket?
    private let riviumPushConfig: RiviumPushConfig
    private let appId: String
    private let deviceId: String
    private let appIdentifier: String
    private let subscriptionId: String?
    private var hasSubscribedOnce: Bool = false  // Track if initial subscription is done

    // Strong reference to connection listener to prevent deallocation
    private var connectionListener: ConnectionListener?

    // Strong references to message handlers to prevent deallocation
    private var messageHandlers: [PNMessageHandler] = []

    weak var delegate: PNSocketManagerDelegate?

    protocol PNSocketManagerDelegate: AnyObject {
        func pnSocketManager(_ manager: PNSocketManager, didConnect success: Bool)
        func pnSocketManager(_ manager: PNSocketManager, didDisconnect error: Error?)
        func pnSocketManager(_ manager: PNSocketManager, didReceiveMessage message: String, channel: String)
    }

    /// Timings for the socket. Keepalive is short so a dead connection on a
    /// lossy network is noticed quickly; the server resends anything missed.
    static let keepAliveSeconds: UInt16 = 30
    static let connectTimeoutSeconds: TimeInterval = 15
    static let pingTimeoutSeconds: TimeInterval = 15

    private let endpointMemory: MqttEndpointMemory
    private let networkKind: () -> NetworkKind

    init(
        config: RiviumPushConfig,
        appId: String,
        deviceId: String,
        appIdentifier: String = "_default",
        subscriptionId: String? = nil,
        endpointMemory: MqttEndpointMemory = MqttEndpointMemory(),
        networkKind: @escaping () -> NetworkKind = { .other }
    ) {
        self.riviumPushConfig = config
        self.appId = appId
        self.deviceId = deviceId
        self.appIdentifier = appIdentifier
        self.subscriptionId = subscriptionId
        self.endpointMemory = endpointMemory
        self.networkKind = networkKind
        super.init()
    }

    /// Endpoints to try for the current network type, best first.
    func orderedEndpoints() -> [PNEndpoint] {
        return MqttEndpointOrder.ordered(
            server: riviumPushConfig.pnEndpoints,
            fallback: riviumPushConfig.defaultPNEndpoint,
            lastGood: endpointMemory.lastGood(for: networkKind())
        )
    }

    /// Build the socket configuration.
    func makePNConfig(clientId: String) -> PNConfig {
        let c = riviumPushConfig
        var builder = PNConfigBuilder()
            .gateway(c.pnHost)
            .port(c.pnPort)
            .secure(c.pnSecure)
            .endpoints(orderedEndpoints())
            .clientId(clientId)
            .heartbeatInterval(PNSocketManager.keepAliveSeconds)
            .connectionTimeout(PNSocketManager.connectTimeoutSeconds)
            .pingTimeout(PNSocketManager.pingTimeoutSeconds)
            .freshStart(true)
            .autoReconnect(c.autoReconnect)
            .maxReconnectAttempts(max(0, c.maxReconnectAttempts))  // 0 = never give up
            .reconnectDelay(Double(max(c.initialReconnectDelayMs, 100)) / 1000.0)
            .maxReconnectDelay(Double(max(c.maxReconnectDelayMs, c.initialReconnectDelayMs, 100)) / 1000.0)

        // JWT token auth (per-device authentication)
        if let token = c.pnToken {
            builder = builder.auth(.basic(username: "jwt", password: token))
        }
        return builder.build()
    }

    /// Connect to gateway
    func connect() {
        let bundleHash = String(abs(Bundle.main.bundleIdentifier?.hashValue ?? 0), radix: 16)
        let clientId = "rp_\(appId)_\(deviceId)_\(bundleHash)"

        if riviumPushConfig.pnToken == nil {
            print("[PNSocketManager] WARNING: No PN token available - connection will likely fail with 'notAuthorized'")
        }

        let pnConfig = makePNConfig(clientId: clientId)
        print("[PNSocketManager] connect() - endpoints: \(pnConfig.endpoints)")

        // Initialize RiviumPush protocol (closes any previous socket first)
        PNProtocolClient.initialize(pnConfig)
        socket = PNProtocolClient.socket()

        // Add connection listener (must keep strong reference to prevent deallocation)
        connectionListener = ConnectionListener(manager: self)
        socket?.addConnectionListener(connectionListener!)

        // Add error listener
        socket?.addErrorListener(PNErrorHandler { error in
            print("[PNSocketManager] Error: \(error.message)")
        })

        socket?.open()
    }

    /// Disconnect from gateway
    func disconnect() {
        socket?.close()
        socket = nil
        connectionListener = nil
        messageHandlers.removeAll()
        hasSubscribedOnce = false  // Reset subscription state
        PNProtocolClient.shutdown()
        print("[PNSocketManager] Disconnected")
    }

    /// Reconnect now with the backoff reset.
    ///
    /// - Parameter force: also drop a live connection (network path changed).
    ///   Without it a connected socket is only probed with a ping.
    /// After `disconnect()` this opens a new socket.
    func reconnectNow(force: Bool = false) {
        print("[PNSocketManager] reconnectNow(force: \(force))")
        guard let socket = socket else {
            connect()
            return
        }
        socket.setEndpoints(orderedEndpoints())
        if !force && socket.state == .connected {
            socket.probe()
            return
        }
        socket.reconnect(force: force)
    }

    /// Remember the endpoint that just worked for this network type.
    private func rememberConnectedEndpoint() {
        guard let endpoint = socket?.connectedEndpoint else { return }
        endpointMemory.remember(endpoint, for: networkKind())
    }

    /// Subscribe to device channels (called only on first connect, not reconnects).
    /// On reconnects, PNSocket.resubscribeChannels() handles re-subscribing
    /// from its activeChannels set automatically.
    private func subscribeToChannels() {
        // Per-install subscription topic — primary delivery channel for every
        // device-targeted message after the subscriptionId migration.
        let subscriptionChannel = subscriptionId.map { "rivium_push/\(appId)/sub/\($0)" }
        let broadcastChannel = "rivium_push/\(appId)/broadcast"

        // DEPRECATED: legacy device-scoped topic. The backend stopped
        // publishing here after the subscriptionId migration. Kept subscribed
        // only to keep older test builds / out-of-tree backends working; will
        // be removed in a future SDK release.
        let deviceChannel = "rivium_push/\(appId)/\(deviceId)/\(appIdentifier)"

        // Shared message handler factory — strong refs are stored in
        // messageHandlers to prevent deallocation while the socket is alive.
        let makeHandler: () -> PNMessageHandler = { [weak self] in
            return PNMessageHandler { [weak self] message in
                guard let self = self else { return }
                let payload = message.payloadAsString()
                print("[PNSocketManager] Message received on \(message.channel): \(payload)")
                self.delegate?.pnSocketManager(self, didReceiveMessage: payload, channel: message.channel)
            }
        }

        if let channel = subscriptionChannel {
            let subHandler = makeHandler()
            messageHandlers.append(subHandler)
            print("[PNSocketManager] Subscribing to \(channel)")
            socket?.stream(channel, mode: .reliable, listener: subHandler)
        }

        let broadcastHandler = makeHandler()
        messageHandlers.append(broadcastHandler)
        print("[PNSocketManager] Subscribing to \(broadcastChannel)")
        socket?.stream(broadcastChannel, mode: .reliable, listener: broadcastHandler)

        // Legacy stream — DEPRECATED, see comment above.
        let deviceHandler = makeHandler()
        messageHandlers.append(deviceHandler)
        print("[PNSocketManager] Subscribing to (deprecated) \(deviceChannel)")
        socket?.stream(deviceChannel, mode: .reliable, listener: deviceHandler)

        print("[PNSocketManager] Subscribed to channels (sub=\(subscriptionChannel != nil), legacy device topic kept for compat)")
    }

    var isConnected: Bool {
        return socket?.isConnected() ?? false
    }

    /// Check if the current config matches the given config (host, port, token).
    /// Used to decide whether to reconnect the existing socket or recreate it.
    func hasMatchingConfig(_ config: RiviumPushConfig) -> Bool {
        return riviumPushConfig.pnHost == config.pnHost
            && riviumPushConfig.pnPort == config.pnPort
            && riviumPushConfig.pnToken == config.pnToken
            && riviumPushConfig.pnSecure == config.pnSecure
            && riviumPushConfig.pnEndpoints == config.pnEndpoints
    }

    // MARK: - Connection Listener

    private class ConnectionListener: PNConnectionListener {
        weak var manager: PNSocketManager?

        init(manager: PNSocketManager) {
            self.manager = manager
        }

        func onStateChanged(_ state: PNState) {
            print("[PNSocketManager] State: \(state)")
        }

        func onConnected() {
            print("[PNSocketManager] Connected")
            manager?.rememberConnectedEndpoint()
            // Subscribe only on the first connection.
            // On reconnects, PNSocket.resubscribeChannels() handles
            // re-subscribing from its activeChannels set automatically.
            if manager?.hasSubscribedOnce == false {
                manager?.subscribeToChannels()
                manager?.hasSubscribedOnce = true
            } else {
                print("[PNSocketManager] Reconnected - PNSocket handles resubscription automatically")
            }
            if let manager = manager {
                manager.delegate?.pnSocketManager(manager, didConnect: true)
            }
        }

        func onDisconnected(reason: String?) {
            print("[PNSocketManager] Disconnected: \(reason ?? "unknown")")
            if let manager = manager {
                manager.delegate?.pnSocketManager(manager, didDisconnect: nil)
            }
        }

        func onReconnecting(attempt: Int, nextRetryMs: Int) {
            print("[PNSocketManager] Reconnecting: attempt=\(attempt)")
        }
    }
}
