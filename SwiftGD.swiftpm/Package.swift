// swift-tools-version: 5.5
import PackageDescription

let package = Package(
    name: "SwiftGD",
    platforms: [
        .iOS("15.2")
    ],
    products: [
        .iOSApplication(
            name: "SwiftGD",
            targets: ["SwiftGD"],
            bundleIdentifier: "com.example.SwiftGD",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .star),
            accentColor: .presetColor(.blue),
            supportedDeviceFamilies: [.pad, .phone],
            supportedInterfaceOrientations: [.portrait]
        )
    ],
    targets: [
        .executableTarget(
            name: "SwiftGD",
            path: "Sources"
        )
    ]
)
