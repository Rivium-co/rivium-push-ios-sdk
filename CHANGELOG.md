# Changelog

## [0.1.11] - 2026-09-09

### Fixed
- 0.1.10's `RiviumPushSDK/Extension` subspec crashed apps at launch with `Symbol not found: RiviumPushSDK.RiviumPush.shared`. Both subspecs built a framework named `RiviumPushSDK`, so the extension's cut-down copy overwrote the app's when embedded. The extension half now ships as a separate pod, `RiviumPushSDKExtension`, with its own module name.

### Changed
- **Migration from 0.1.10:** in your extension target, replace `pod 'RiviumPushSDK/Extension'` with `pod 'RiviumPushSDKExtension'`, and `import RiviumPushSDK` with `import RiviumPushSDKExtension`.

## [0.1.10] - 2026-09-08

### Fixed
- `RiviumPushSDK` could not be linked into a Notification Service Extension — the SDK uses `UIApplication.shared`, which app extensions may not call, so delivery confirmation did not build. The pod is now split: `RiviumPushSDK` (unchanged, for your app) and `RiviumPushSDK/Extension`, which carries only `RiviumPushServiceExtension` and is extension-safe.

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.9] - 2026-09-08

### Added
- Delivery confirmation from a Notification Service Extension. Set `appGroup` in the config and the SDK shares the device identity with the extension, so the server learns a notification actually arrived.
- `appGroup` on `RiviumPushConfig.builder()`.

### Fixed
- `RiviumPushServiceExtension` was missing from the Swift Package Manager sources list, so SPM users could not reference it. CocoaPods was unaffected.
- A VoIP token could linger on the device record when PushKit was disabled.

## [0.1.8] - 2026-08-23

### Added
- App build number captured alongside app version.

## [0.1.7] - 2026-08-23

### Added
- Device attributes captured automatically for segment filters.
