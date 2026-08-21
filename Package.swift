// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Thoughtbox",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Thoughtbox", targets: ["Thoughtbox"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.8.0")
    ],
    targets: [
        .executableTarget(
            name: "Thoughtbox",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown")
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
