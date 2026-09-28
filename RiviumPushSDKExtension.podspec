Pod::Spec.new do |s|
  s.name             = 'RiviumPushSDKExtension'
  s.version          = '0.1.14'
  s.summary          = 'Delivery confirmation for Rivium Push, for a Notification Service Extension.'

  s.description      = <<-DESC
    APNs confirms only that Apple accepted a notification, never that it arrived.
    This is the extension-side half of Rivium Push: add it to your Notification
    Service Extension target to report real deliveries.

    It ships separately from RiviumPushSDK on purpose. An app extension may not
    call UIApplication.shared, so the full SDK cannot be linked into one — and a
    subspec cannot solve it, because subspecs share a framework name and the
    extension's copy would overwrite the app's at embed time.
  DESC

  s.homepage         = 'https://rivium.co/cloud/rivium-push'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Rivium' => 'support@rivium.co' }
  s.source           = { :git => 'https://github.com/Rivium-co/rivium-push-ios-sdk.git', :tag => s.version.to_s }

  s.ios.deployment_target = '13.0'
  s.swift_version = '5.0'

  s.source_files = ['Sources/RiviumPushServiceExtension.swift', 'Sources/RiviumPushShared.swift']
  s.frameworks   = 'UserNotifications'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'APPLICATION_EXTENSION_API_ONLY' => 'YES',
  }
end
