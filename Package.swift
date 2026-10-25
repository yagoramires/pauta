// swift-tools-version:6.0
import Foundation
import PackageDescription

// NeyKit vem do checkout do neyhub ao lado (ou NEYHUB_PATH). A identidade de `.package(path:)` é o nome
// da pasta em minúsculas, então derivamos dela: funciona com worktrees.
let neyhub = ProcessInfo.processInfo.environment["NEYHUB_PATH"] ?? "../neyhub"
let hub = URL(fileURLWithPath: neyhub).lastPathComponent.lowercased()
let swift5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Pauta",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Pauta", targets: ["Pauta"]),
        .library(name: "PautaPlugin", type: .dynamic, targets: ["PautaPlugin"]),
    ],
    dependencies: [.package(path: neyhub)],
    targets: [
        .target(name: "PautaCore", dependencies: [.product(name: "NeyKit", package: hub)], path: "Sources/PautaCore", swiftSettings: swift5),
        .executableTarget(
            name: "Pauta",
            dependencies: ["PautaCore", .product(name: "NeyKitApp", package: hub)],
            path: "Sources/Pauta",
            swiftSettings: swift5
        ),
        // Plugin do NeyHub: nunca linka NeyKitApp (classes duplicadas no processo do NeyHub).
        .target(name: "PautaPlugin", dependencies: ["PautaCore", .product(name: "NeyKit", package: hub)], path: "Sources/PautaPlugin", swiftSettings: swift5),
    ]
)
