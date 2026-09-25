// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SmartOrganiser",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "SmartOrganiser", targets: ["SmartOrganiser"])],
    targets: [
        .target(name: "OrganiserCore"),
        .executableTarget(name: "SmartOrganiser", dependencies: ["OrganiserCore"]),
        .testTarget(name: "OrganiserCoreTests", dependencies: ["OrganiserCore"]),
        .testTarget(name: "SmartOrganiserTests", dependencies: ["SmartOrganiser"])
    ],
    swiftLanguageModes: [.v5]
)
