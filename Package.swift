// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FCPXLite",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "FCPXLite",
            path: "Sources/FCPXLite"
        ),
        .testTarget(
            name: "FCPXLiteTests",
            dependencies: ["FCPXLite"],
            path: "Tests/FCPXLiteTests"
        ),
    ]
)
