// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "jjswift",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "JJLib", targets: ["JJLib"]),
    ],
    targets: [
        .target(
            name: "JJLib",
            path: "Sources/jjswift/JJ"
        ),
        .executableTarget(
            name: "jjswift",
            dependencies: ["JJLib"],
            path: "Sources/jjswift",
            exclude: ["JJ"]
        )
    ]
)
