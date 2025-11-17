// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "VolumeGrid",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "VolumeGrid", targets: ["VolumeGrid"])
    ],
    targets: [
        .executableTarget(
            name: "VolumeGrid",
            path: "VolumeGrid",
            resources: [.copy("Assets/icon.png")]
        )
    ]
)
