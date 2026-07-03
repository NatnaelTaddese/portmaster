// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PortMaster",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "PortMaster",
            path: "Sources/PortMaster",
            resources: [.copy("Resources/Fonts")]
        )
    ]
)
