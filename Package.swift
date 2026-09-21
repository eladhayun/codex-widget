// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexWidget",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "CodexWidget", targets: ["CodexWidget"])],
    targets: [
        .target(name: "UsageCore"),
        .executableTarget(name: "CodexWidget", dependencies: ["UsageCore"]),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"]),
        .testTarget(name: "WidgetTests", dependencies: ["CodexWidget", "UsageCore"])
    ]
)
