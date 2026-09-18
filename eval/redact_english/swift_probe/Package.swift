// swift-tools-version: 6.2
import PackageDescription
import Foundation

let sdkPath = ProcessInfo.processInfo.environment["REDACT_SDK_SOURCE"]
    ?? "../../../.cache/redact-evaluation/desert-ant-core-c015d5d95028caba783e802442e30ddd66c9247e"
let package = Package(
    name: "RedactDiagnostic",
    platforms: [.macOS(.v15)],
    dependencies: [.package(name: "SDK", path: sdkPath)],
    targets: [.executableTarget(name: "RedactDiagnostic", dependencies: [
        .product(name: "Redact", package: "SDK"),
        .product(name: "DesertAnt", package: "SDK")
    ])]
)
