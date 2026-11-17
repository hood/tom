// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tom",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Tom",
            path: "Sources/Tom",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
