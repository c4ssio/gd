// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftGD",
    platforms: [
        .iOS("16.0")
    ],
    products: [
        .iOSApplication(
            name: "SwiftGD",
            targets: ["SwiftGD"],
            bundleIdentifier: "com.example.SwiftGD",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .star),
            accentColor: .presetColor(.yellow),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "SwiftGD",
            path: "Sources"
        )
    ]
)
