// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Thoughtbox",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Thoughtbox", targets: ["Thoughtbox"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.8.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.9.2")
    ],
    targets: [
        .executableTarget(
            name: "Thoughtbox",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Thoughtbox",
            resources: [.process("Localizable.xcstrings")]
        ),
        .testTarget(
            name: "ThoughtboxTests",
            dependencies: ["Thoughtbox"],
            path: "Tests/ThoughtboxTests"
        )
    ]
)
