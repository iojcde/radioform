// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RadioformConfiguration",
    platforms: [.macOS(.v13)],
    products: [.library(name: "RadioformConfiguration", targets: ["RadioformConfiguration"])],
    targets: [
        .target(name: "RadioformConfiguration"),
        .testTarget(name: "RadioformConfigurationTests", dependencies: ["RadioformConfiguration"])
    ]
)
