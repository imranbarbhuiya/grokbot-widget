// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GrokbotWidget",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "GrokbotWidget", targets: ["GrokbotWidget"])],
    targets: [.executableTarget(name: "GrokbotWidget"), .testTarget(name: "GrokbotWidgetTests", dependencies: ["GrokbotWidget"])]
)
