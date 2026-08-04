// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TabFiler",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        // ファイルツリーのモデル(FileNode/TabModel/PaneModel/AppState)と、
        // D&Dのドロップ可否判定・ファイル移動/コピーの実行ロジックなど、
        // AppKit/SwiftUIに依存しない純粋なロジックをまとめたライブラリ。
        // ここに切り出すことで swift test がGUIなしで高速・安定に走る。
        .target(
            name: "TabFilerCore",
            path: "Sources/TabFilerCore"
        ),
        .executableTarget(
            name: "TabFiler",
            dependencies: ["TabFilerCore"],
            path: "Sources/TabFiler"
        ),
        .testTarget(
            name: "TabFilerCoreTests",
            dependencies: ["TabFilerCore"],
            path: "Tests/TabFilerCoreTests"
        )
    ]
)
