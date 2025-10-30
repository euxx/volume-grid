// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "VolumeGrid",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "VolumeGrid", targets: ["VolumeGrid"]),
    ],
    targets: [
        .executableTarget(
            name: "VolumeGrid",
            path: "VolumeGrid"
        ),
    ]
)