import Foundation
import PushKit
import CallKit

/// Manages PushKit VoIP push registration and handling
internal class VoIPManager: NSObject {
    private var voipRegistry: PKPushRegistry?
    private var callProvider: CXProvider?

    weak var delegate: VoIPManagerDelegate?

    protocol VoIPManagerDelegate: AnyObject {
        func voipManager(_ manager: VoIPManager, didReceiveToken token: String)
        func voipManager(_ manager: VoIPManager, didReceivePayload payload: [AnyHashable: Any])
        func voipManager(_ manager: VoIPManager, didFailWithError error: Error)
    }

    override init() {
        super.init()
        setupCallKit()
    }

    /// Register for VoIP pushes
    func register() {
        voipRegistry = PKPushRegistry(queue: .main)
        voipRegistry?.delegate = self
        voipRegistry?.desiredPushTypes = [.voIP]
    }

    /// Setup CallKit (required since iOS 13)
    private func setupCallKit() {
        let config: CXProviderConfiguration
        if #available(iOS 14.0, *) {
            config = CXProviderConfiguration()
        } else {
            config = CXProviderConfiguration(localizedName: "RiviumPush")
        }
        config.supportsVideo = false
        config.maximumCallsPerCallGroup = 1
        config.supportedHandleTypes = [.generic]

        callProvider = CXProvider(configuration: config)
        callProvider?.setDelegate(self, queue: .main)
    }

    /// Report incoming call to CallKit (required by Apple)
    /// We immediately end the call since this is just for push notifications
    func reportIncomingCall(uuid: UUID, completion: @escaping (Bool) -> Void) {
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: "RiviumPush")
        update.hasVideo = false
        update.localizedCallerName = "Push Notification"

        callProvider?.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
            if let error = error {
                print("RiviumPush: Failed to report call: \(error)")
                completion(false)
            } else {
                // Immediately end the call
                self?.callProvider?.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
                completion(true)
            }
        }
    }
}

// MARK: - PKPushRegistryDelegate
extension VoIPManager: PKPushRegistryDelegate {
    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        guard type == .voIP else { return }

        let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        print("RiviumPush: VoIP token received: \(token)")
        delegate?.voipManager(self, didReceiveToken: token)
    }

    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        guard type == .voIP else {
            completion()
            return
        }

        print("RiviumPush: VoIP push received")

        // Must report a call to CallKit (Apple requirement since iOS 13)
        let callUUID = UUID()
        reportIncomingCall(uuid: callUUID) { [weak self] success in
            if success {
                self?.delegate?.voipManager(self!, didReceivePayload: payload.dictionaryPayload)
            }
            completion()
        }
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        print("RiviumPush: VoIP token invalidated")
    }
}

// MARK: - CXProviderDelegate
extension VoIPManager: CXProviderDelegate {
    func providerDidReset(_ provider: CXProvider) {}

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        action.fulfill()
    }
}
