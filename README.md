# TabFiler

macOS 向けのタブ式ファイラー。Windows の [Tablacus Explorer](https://tablacus.github.io/explorer.html) のような、タブ＋ウィンドウ分割で複数フォルダを行き来できるファイラーを目指している。Finder のタブでは足りない用途向け。

## 主な機能

- タブによる複数ディレクトリの並行表示（`Cmd+T` で追加 / `Cmd+W` で閉じる）
- ウィンドウ分割（`Cmd+D` で右に分割 / `Cmd+Shift+W` でペインを閉じる）。ペインごとに独立したタブを持つ
- 階層ツリー表示（`NSOutlineView`、遅延展開）
- 戻る / 進む / 上の階層へ（`Cmd+[` / `Cmd+]` / `Cmd+↑`、空白部分のダブルクリックでも上へ）
- ダブルクリックでフォルダを開く・ファイル/アプリを起動、右クリックメニュー（開く / Finder で表示）
- 表示中フルパスのクリップボードコピー

## 技術構成

- SwiftUI + AppKit ハイブリッド。ツリーは `NSOutlineView` を `NSViewRepresentable` で組み込み
- Swift Package Manager の実行ファイルターゲット。`Package.swift` を Xcode で直接開いて実行できる
- 対象: macOS 13 以降

## ビルド・実行

```sh
swift build
swift run
```

または Xcode で `Package.swift` を開いて実行する。

## 今後

- アプリアイコン作成と `.app` パッケージ化（Dock 常駐用）
