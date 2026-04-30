Pod::Spec.new do |s|
  s.name             = 'RiviumPushSDK'
  s.version          = '0.1.4'
  s.summary          = 'Rivium Push Notification SDK for iOS'
  s.description      = <<-DESC
    Rivium Push is a comprehensive push notification SDK for iOS with support for:
    - Rich notifications (images, action buttons)
    - In-app messages
    - Inbox/Message center
    - Topic subscriptions
    - User management
    - VoIP push for background delivery
  DESC

  s.homepage         = 'https://rivium.co'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Rivium' => 'support@rivium.co' }

  s.source           = { :git => 'https://github.com/Rivium-co/rivium-push-ios-sdk.git', :tag => s.version.to_s }

  s.ios.deployment_target = '13.0'
  s.swift_version = '5.0'

  # Source files - exclude PNProtocol/ since it comes from the PNProtocol pod dependency
  s.source_files = 'Sources/**/*.swift'
  s.exclude_files = 'Sources/PNProtocol/**/*'

  # Dependencies
  s.dependency 'PNProtocol', '~> 0.2'
  s.dependency 'CocoaMQTT', '~> 2.1'

  # Frameworks required
  s.frameworks = 'UIKit', 'UserNotifications', 'PushKit', 'CallKit'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
