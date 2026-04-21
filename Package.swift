// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "RiviumPush",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "RiviumPush",
            targets: ["RiviumPush"]
        ),
    ],
    dependencies: [
        // PN Protocol - Rivium Push's messaging protocol layer
        .package(url: "https://github.com/Rivium-co/pn-protocol-ios.git", from: "0.2.1"),
    ],
    targets: [
        .target(
            name: "RiviumPush",
            dependencies: [.product(name: "PNProtocol", package: "pn-protocol-ios")],
            path: "Sources",
            sources: [
                "RiviumPush.swift",
                "RiviumPushConfig.swift",
                "RiviumPushDelegate.swift",
                "RiviumPushMessage.swift",
                "RiviumPushError.swift",
                "RiviumPushLogger.swift",
                "ApiClient.swift",
                "PNSocketManager.swift",
                "VoIPManager.swift",
                "NotificationManager.swift",
                "Utils/RiviumPushDispatch.swift",
                "Utils/NetworkConfig.swift",
                "InApp/InAppMessage.swift",
                "InApp/InAppMessageManager.swift",
                "InApp/InAppMessageView.swift",
                "Inbox/InboxMessage.swift",
                "Inbox/InboxManager.swift",
                "ABTesting/ABTest.swift",
                "ABTesting/ABTestingManager.swift",
                "Internal/SdkCredentials.swift"
            ]
        ),
        .testTarget(
            name: "RiviumPushTests",
            dependencies: ["RiviumPush"],
            path: "Tests"
        ),
    ]
)
