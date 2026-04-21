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

    init(config: RiviumPushConfig, appId: String, deviceId: String, appIdentifier: String = "_default") {
        self.riviumPushConfig = config
        self.appId = appId
        self.deviceId = deviceId
        self.appIdentifier = appIdentifier
        super.init()
    }

    /// Connect to gateway
    func connect() {
        let bundleHash = String(abs(Bundle.main.bundleIdentifier?.hashValue ?? 0), radix: 16)
        let clientId = "rp_\(appId)_\(deviceId)_\(bundleHash)"

        print("[PNSocketManager] connect() called - host: \(riviumPushConfig.pnHost), port: \(riviumPushConfig.pnPort)")
        print("[PNSocketManager] Token present: \(riviumPushConfig.pnToken != nil)")

        // Build PNConfig from RiviumPushConfig
        var configBuilder = PNConfigBuilder()
            .gateway(riviumPushConfig.pnHost)
            .port(riviumPushConfig.pnPort)
            .clientId(clientId)
            .heartbeatInterval(60)
            .connectionTimeout(30)
            .freshStart(true)
            .autoReconnect(true)
            .maxReconnectAttempts(10)
            .reconnectDelay(1.0)
            .maxReconnectDelay(300.0)
            .secure(riviumPushConfig.pnSecure)  // Use TLS/SSL from server config

        // Set JWT token auth if available (per-device authentication)
        if let token = riviumPushConfig.pnToken {
            print("[PNSocketManager] Using JWT token for PN Protocol authentication (length: \(token.count))")
            configBuilder = configBuilder.auth(.basic(username: "jwt", password: token))
        } else {
            print("[PNSocketManager] WARNING: No PN token available - connection will likely fail with 'notAuthorized'")
        }

        let pnConfig = configBuilder.build()

        // Initialize RiviumPush protocol
        PNProtocolClient.initialize(pnConfig)
        socket = PNProtocolClient.socket()
        print("[PNSocketManager] Socket created: \(socket != nil)")

        // Add connection listener (must keep strong reference to prevent deallocation)
        connectionListener = ConnectionListener(manager: self)
        socket?.addConnectionListener(connectionListener!)

        // Add error listener
        socket?.addErrorListener(PNErrorHandler { error in
            print("[PNSocketManager] Error: \(error.message)")
        })

        // Open connection
        print("[PNSocketManager] Opening connection to \(riviumPushConfig.pnHost):\(riviumPushConfig.pnPort)")
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

    /// Trigger immediate reconnection without destroying the socket.
    /// Preserves activeChannels so PNSocket can resubscribe automatically.
    func reconnectNow() {
        print("[PNSocketManager] reconnectNow() called")
        socket?.reconnectImmediately()
    }

    /// Subscribe to device channels (called only on first connect, not reconnects).
    /// On reconnects, PNSocket.resubscribeChannels() handles re-subscribing
    /// from its activeChannels set automatically.
    private func subscribeToChannels() {
        let deviceChannel = "rivium_push/\(appId)/\(deviceId)/\(appIdentifier)"
        let broadcastChannel = "rivium_push/\(appId)/broadcast"

        // Create handlers and keep strong references to prevent deallocation
        let deviceHandler = PNMessageHandler { [weak self] message in
            guard let self = self else { return }
            let payload = message.payloadAsString()
            print("[PNSocketManager] Message received on \(message.channel): \(payload)")
            self.delegate?.pnSocketManager(self, didReceiveMessage: payload, channel: message.channel)
        }
        messageHandlers.append(deviceHandler)

        let broadcastHandler = PNMessageHandler { [weak self] message in
            guard let self = self else { return }
            let payload = message.payloadAsString()
            print("[PNSocketManager] Message received on \(message.channel): \(payload)")
            self.delegate?.pnSocketManager(self, didReceiveMessage: payload, channel: message.channel)
        }
        messageHandlers.append(broadcastHandler)

        print("[PNSocketManager] Subscribing to \(deviceChannel)")
        socket?.stream(deviceChannel, mode: .reliable, listener: deviceHandler)

        print("[PNSocketManager] Subscribing to \(broadcastChannel)")
        socket?.stream(broadcastChannel, mode: .reliable, listener: broadcastHandler)

        print("[PNSocketManager] Subscribed to both channels")
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
            // Subscribe only on the first connection.
            // On reconnects, PNSocket.resubscribeChannels() handles
            // re-subscribing from its activeChannels set automatically.
            if manager?.hasSubscribedOnce == false {
                manager?.subscribeToChannels()
                manager?.hasSubscribedOnce = true
            } else {
                print("[PNSocketManager] Reconnected - PNSocket handles resubscription automatically")
            }
            manager?.delegate?.pnSocketManager(manager!, didConnect: true)
        }

        func onDisconnected(reason: String?) {
            print("[PNSocketManager] Disconnected: \(reason ?? "unknown")")
            manager?.delegate?.pnSocketManager(manager!, didDisconnect: nil)
        }

        func onReconnecting(attempt: Int, nextRetryMs: Int) {
            print("[PNSocketManager] Reconnecting: attempt=\(attempt)")
        }
    }
}
