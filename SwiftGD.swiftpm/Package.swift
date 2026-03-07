// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftGD",
    platforms: [
        .iOS("16.0"),
        .macOS("13.0")
    ],
    targets: [
        .executableTarget(
            name: "SwiftGD",
            path: "Sources"
        )
    ]
)
