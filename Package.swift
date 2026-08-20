// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Thoughtbox",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Thoughtbox", targets: ["Thoughtbox"])
    ],
    targets: [
        .executableTarget(
            name: "Thoughtbox",
            path: "Sources/Thoughtbox"
        ),
        .testTarget(
            name: "ThoughtboxTests",
            dependencies: ["Thoughtbox"],
            path: "Tests/ThoughtboxTests"
        )
    ]
)

