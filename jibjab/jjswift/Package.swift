// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "jjswift",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "jjswift",
            path: "Sources/jjswift"
        )
    ]
)
