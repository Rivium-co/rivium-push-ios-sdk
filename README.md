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

## Requirements

- iOS 13.0+
- Swift 5.7+
- Xcode 14+

## VoIP Push (Optional)

For calling apps (Jitsi, WebRTC), add the [RiviumPush VoIP SDK](https://github.com/Rivium-co/rivium-push-voip-ios-sdk):

```swift
// Swift Package Manager
.package(url: "https://github.com/Rivium-co/rivium-push-voip-ios-sdk.git", from: "0.1.1")

// CocoaPods
pod 'RiviumPushVoip', '~> 0.1'
```

```swift
import RiviumPushVoip

// Configure
let voipConfig = VoipConfig(appName: "MyApp", supportsVideo: true)
RiviumPushVoip.shared.initialize(config: voipConfig)
RiviumPushVoip.shared.delegate = self

// Enable VoIP in RiviumPush config (same API key from Rivium Console)
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

Send push with data to trigger VoIP incoming call:

```json
{
  "type": "voip_call",
  "callerName": "John Doe",
  "callerId": "user_456",
  "callerAvatar": "https://example.com/avatar.jpg",
  "callType": "video"
}
```

The `type: "voip_call"` is the system trigger (fixed). Caller data keys are configurable via VoIP SDK config.

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
