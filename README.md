# Rivium Push iOS SDK

Native iOS SDK for real-time push notifications via pn-protocol. No Firebase dependency.

## Features

- Real-time push via pn-protocol
- APNs support for background delivery
- Rich notifications with images and action buttons
- In-app messaging (modal, banner, fullscreen, card)
- Message inbox with persistent storage
- Topic subscription for targeted messaging
- A/B testing support
- User segmentation
- Analytics and delivery tracking
- VoIP push support (optional)

## Installation

### Swift Package Manager (recommended)

In Xcode: File → Add Package Dependencies → Enter:

```
https://github.com/Rivium-co/rivium-push-ios-sdk.git
```

Select version `0.1.0` or later.

### CocoaPods

```ruby
pod 'RiviumPushSDK', '~> 0.1.0'
```

## Quick Start

### 1. Initialize in AppDelegate

```swift
import RiviumPush

func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

    let config = RiviumPushConfig(apiKey: "your_api_key_here")
    RiviumPush.shared.initialize(config: config)
    RiviumPush.shared.delegate = self

    // Request notification permission
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
        if granted {
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    // Register device
    RiviumPush.shared.register(userId: "user_123") // userId is optional

    return true
}
```

### 2. Forward APNs token

```swift
func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    RiviumPush.shared.setAPNsToken(deviceToken)
}
```

### 3. Set up delegate

```swift
extension AppDelegate: RiviumPushDelegate {

    func riviumPush(_ riviumPush: RiviumPush, didRegisterWithDeviceId deviceId: String) {
        print("Registered: \(deviceId)")
    }

    func riviumPush(_ riviumPush: RiviumPush, didReceiveMessage message: RiviumPushMessage) {
        print("Message: \(message.title ?? "")")
    }

    func riviumPush(_ riviumPush: RiviumPush, didTapNotification message: RiviumPushMessage) {
        // Handle notification tap
    }

    func riviumPush(_ riviumPush: RiviumPush, didChangeConnectionState connected: Bool) {
        print("Connected: \(connected)")
    }

    func riviumPush(_ riviumPush: RiviumPush, didFailWithError error: Error) {
        print("Error: \(error)")
    }
}
```

## Device Management

### User ID

```swift
// Set user ID (after login)
RiviumPush.shared.setUserId("user_123")

// Clear user ID (after logout)
RiviumPush.shared.clearUserId()
```

### Signed user tokens

Optional. If your backend issues Rivium user tokens, give the SDK a `tokenProvider` and it sends the token with every request, so the server can verify which user a device belongs to. It is the same token, and the same function, you pass to Rivium Chat.

```swift
// Returns the token from your backend, or nil when no user is signed in.
let tokenProvider: () async throws -> String? = {
    try await MyBackend.fetchRiviumToken()
}

let config = RiviumPushConfig(apiKey: "rv_live_your_api_key", tokenProvider: tokenProvider)
RiviumPush.shared.initialize(config: config)

RiviumPush.shared.onAuthError = { event in
    print("Rivium token problem: \(event.code)")  // e.g. send the user to login
}
```

The SDK caches the token, renews it shortly before it expires and forgets it on `clearUserId()`. You can also set the provider later with `setTokenProvider(_:)`, or pass a token you fetched yourself with `setUserToken(_:)`. Without a provider nothing changes.

### Topics

```swift
// Subscribe
RiviumPush.shared.subscribeTopic("news")

// Unsubscribe
RiviumPush.shared.unsubscribeTopic("news")
```

## In-App Messages

```swift
// Trigger messages
RiviumPush.shared.triggerInAppOnAppOpen()
RiviumPush.shared.triggerInAppEvent("viewed_product")

// Set up callback
RiviumPush.shared.setInAppMessageCallback(handler)
```

## Message Inbox

```swift
// Fetch messages
RiviumPush.shared.getInboxMessages(
    filter: InboxFilter(limit: 50),
    onSuccess: { response in
        let messages = response.messages
        let unread = response.unreadCount
    },
    onError: { error in print(error) }
)

// Real-time updates
RiviumPush.shared.setInboxCallback(handler)

// Mark as read
RiviumPush.shared.markInboxMessageAsRead(messageId: "msg_123")

// Get unread count
let count = RiviumPush.shared.getInboxManager().getUnreadCount()
```

## A/B Testing

```swift
let manager = RiviumPush.shared.getABTestingManager()

// Get active tests
manager.getActiveTests { result in
    // handle tests
}

// Get variant assignment
manager.getVariant(testId: "test_123") { result in
    if case .success(let variant) = result {
        print("Assigned to: \(variant.variantName)")
    }
}

// Track events
manager.trackEvent(testId: "test_123", variantId: "variant_456", event: .clicked) { _ in }
```

## Configuration

```swift
let config = RiviumPushConfig.builder(apiKey: "your_key")
    .usePushKit(false)           // VoIP push (only for calling apps)
    .useAPNs(true)               // Standard APNs (recommended)
    .showNotificationInForeground(true)
    .autoConnect(true)
    .autoReconnect(true)
    .build()
```

| Option | Default | Description |
|--------|---------|-------------|
| `usePushKit` | `false` | Enable VoIP push (calling apps only) |
| `useAPNs` | `true` | Enable standard APNs |
| `showNotificationInForeground` | `false` | Show notifications when app is active |
| `autoConnect` | `true` | Auto-connect when app enters foreground |
| `autoReconnect` | `true` | Auto-reconnect with exponential backoff |
| `autoRefresh` | `true` | Refresh the registration on launch when it may be stale (see below) |
| `appGroup` | `nil` | App Group shared with a Notification Service Extension, for delivery confirmation |

### Automatic registration refresh

Once this install has registered, `initialize(config:)` keeps the server's device record fresh on its own. It re-sends the registration in the background when 24 hours have passed since the last successful one, or when the app version or build, the SDK version, the push token or the user id has changed; otherwise it does nothing. It never prompts for notification permission, and only runs when permission was already granted. An explicit `register()` always registers. Turn it off with `autoRefresh: false`.

## Delivery Confirmation

APNs only confirms that Apple *accepted* a notification, not that it reached the device. The SDK reports a real delivery (`POST /receipts/delivered`) whenever it sees a message:

| How the message arrived | Reported by | Needs |
|--------|---------|-------------|
| SDK socket (app in foreground) | the SDK | nothing |
| APNs, app in foreground | the SDK, from `willPresent` | the SDK as `UNUserNotificationCenter` delegate, or a call to `handleRemoteNotification(userInfo:)` from your own |
| APNs, user taps it | the SDK, from `handleNotificationResponse` | nothing |
| APNs, app in background or not running | your Notification Service Extension | `RiviumPushSDKExtension` + an App Group |

iOS does not run your app when a notification arrives in the background, so **background APNs deliveries are confirmed only with a Notification Service Extension**. Add the extension target, `pod 'RiviumPushSDKExtension'` to it, enable the same App Group on both targets, pass it as `appGroup` in the config, and call `RiviumPushServiceExtension.didReceive(_:apiKey:appGroup:)` from the extension (see the doc comment on `RiviumPushServiceExtension`).

Each message is reported once: the app and the extension share a small list of reported message ids through the App Group, so a notification the extension already confirmed is not reported again when the app shows or opens it.

If you handle silent pushes, forward them too:

```swift
func application(_ application: UIApplication,
                 didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                 fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    RiviumPush.shared.handleRemoteNotification(userInfo: userInfo)
    completionHandler(.noData)
}
```

### Wrapper SDKs

`wrapperSdkName` / `wrapperSdkVersion` exist for Rivium's official Flutter and React Native wrappers, which report their own identity instead of the native one. Apps should not set them. `RiviumPush.sdkVersion` returns the native SDK version.

## Requirements

- iOS 13.0+
- Swift 5.7+
- Xcode 14+

## VoIP Push (Optional)

For calling apps (Jitsi, WebRTC), add the [RiviumPush VoIP SDK](https://github.com/Rivium-co/rivium-push-voip-ios-sdk):

```swift
// Swift Package Manager
.package(url: "https://github.com/Rivium-co/rivium-push-voip-ios-sdk.git", from: "0.1.2")

// CocoaPods
pod 'RiviumPushVoip', '~> 0.1'
```

```swift
import RiviumPushVoip

// Initialize VoIP SDK
let voipConfig = VoipConfig(appName: "MyApp", supportsVideo: true)
RiviumPushVoip.shared.initialize(config: voipConfig)
RiviumPushVoip.shared.delegate = self

// Enable VoIP in RiviumPush config
let config = RiviumPushConfig.builder(apiKey: "rv_live_your_api_key")
    .usePushKit(true)
    .build()
```

```swift
extension AppDelegate: RiviumPushVoipDelegate {
    func voip(_ voip: RiviumPushVoip, didAcceptCall callData: VoipCallData) {
        // Connect to your calling service
    }

    func voip(_ voip: RiviumPushVoip, didDeclineCall callData: VoipCallData) {
        // Handle decline
    }
}
```

To trigger an incoming call, send a push with `type: "voip_call"` in the data:

```json
{
  "title": "Incoming Call",
  "body": "John Doe is calling",
  "data": {
    "type": "voip_call",
    "callerName": "John Doe",
    "callerId": "user_456",
    "callerAvatar": "https://example.com/avatar.jpg",
    "callType": "video"
  }
}
```

The `type: "voip_call"` triggers VoIP delivery (PushKit). Without it, the message is delivered as a regular push notification. See the [VoIP SDK README](https://github.com/Rivium-co/rivium-push-voip-ios-sdk) for full setup guide.

The Push SDK works independently without VoIP. VoIP is only needed for apps with real calling features.

## Example App

The `Example/` folder contains a complete demo app with:
- Push notification receiving
- In-app message triggers
- Inbox management
- A/B test variant assignment
- VoIP calling (toggle on/off)
- Settings and debugging tools

## Links

- [Rivium Push](https://rivium.co/cloud/rivium-push) - Learn more about Rivium Push
- [Documentation](https://rivium.co/cloud/rivium-push/docs/quick-start) - Full documentation and guides
- [Rivium Console](https://console.rivium.co) - Manage your push notifications

## License

MIT License - see [LICENSE](LICENSE) for details.
