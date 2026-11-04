// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacKitCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MacKitCore", targets: ["MacKitCore"])],
    targets: [
        .target(name: "MacKitCore")
    ]
)
