# TabFiler

> **Work in progress** — actively under development, features and APIs may change.

A tabbed file browser for macOS. Aims to be like Windows' [Tablacus Explorer](https://tablacus.github.io/explorer.html) — tabs plus split panes for moving between multiple folders — for cases where Finder's tabs aren't enough.

[日本語版 README](README.ja.md)

## Features

- Multiple directories side by side via tabs (`Cmd+T` to add / `Cmd+W` to close)
- Split panes (`Cmd+D` to split right / `Cmd+Shift+W` to close a pane). Each pane has its own independent tabs
- Hierarchical tree view (`NSOutlineView`, lazy expansion)
- Back / forward / up a level (`Cmd+[` / `Cmd+]` / `Cmd+↑`, or double-click empty space to go up)
- Double-click to open folders / launch files and apps; right-click menu (open / reveal in Finder)
- Copy the current full path to the clipboard

## Tech Stack

- SwiftUI + AppKit hybrid. The tree view wraps `NSOutlineView` via `NSViewRepresentable`
- Swift Package Manager executable target. `Package.swift` can be opened and run directly in Xcode
- Target: macOS 13+

## Build & Run

```sh
swift build
swift run
```

Or open `Package.swift` in Xcode and run it.

## Roadmap

- App icon and `.app` packaging (for keeping it in the Dock)
