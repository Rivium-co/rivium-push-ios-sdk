Pod::Spec.new do |s|
  s.name             = 'RiviumPushSDK'
  s.version          = '0.1.10'
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

  s.default_subspecs = 'Core'

  # The full SDK, for your app target.
  s.subspec 'Core' do |ss|
    # exclude PNProtocol/ since it comes from the PNProtocol pod dependency
    ss.source_files = 'Sources/**/*.swift'
    ss.exclude_files = 'Sources/PNProtocol/**/*'

    ss.dependency 'PNProtocol', '~> 0.2'
    ss.dependency 'CocoaMQTT', '~> 2.1'

    ss.frameworks = 'UIKit', 'UserNotifications', 'PushKit', 'CallKit'
  end

  # Delivery confirmation, for a Notification Service Extension target:
  #
  #   target 'Notification Service Extension' do
  #     pod 'RiviumPushSDK/Extension'
  #   end
  #
  # An app extension may not use UIApplication.shared, so linking Core into one
  # fails to compile. This subspec carries only RiviumPushServiceExtension,
  # which needs nothing beyond Foundation and UserNotifications, and is built
  # with APPLICATION_EXTENSION_API_ONLY so that stays true.
  s.subspec 'Extension' do |ss|
    ss.source_files = 'Sources/RiviumPushServiceExtension.swift'
    ss.frameworks = 'UserNotifications'
    ss.pod_target_xcconfig = { 'APPLICATION_EXTENSION_API_ONLY' => 'YES' }
  end

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
