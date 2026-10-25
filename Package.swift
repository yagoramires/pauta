// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Pauta",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Pauta",
            path: "Sources/Pauta",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
