// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TabFiler",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "TabFiler",
            path: "Sources/TabFiler"
        )
    ]
)
