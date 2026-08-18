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
- **Drag and drop to move or copy files** (see below)

## Drag and Drop

Drag files/folders in the tree onto another folder to move them. **Hold Option while dropping to copy instead** (same convention as Finder). Drops across panes work too, so you can split the window, open a different folder in each pane, and move things straight across.

Several guards are in place to avoid accidents:

- Drops onto **non-writable folders** are rejected
- Dropping a folder **into itself or into its own subtree** is rejected. Both paths are resolved to their real paths before comparing, so the check can't be bypassed through a symlink
- As defense in depth if that check is ever bypassed, copying aborts when the destination hierarchy gets **abnormally deep**
- Dropping items that are **already in the destination folder** does nothing
- Batch operations of **more than 50 files** ask for confirmation first
- On a name collision you get a **skip / keep both / replace / cancel** dialog, showing the size and modification date of both the existing and the incoming file

**There is no undo.** If an operation fails partway through, completed work is not rolled back; instead the result dialog reports exactly how far it got and where it stopped.

## Tech Stack

- SwiftUI + AppKit hybrid. The tree view wraps `NSOutlineView` via `NSViewRepresentable`
- Swift Package Manager executable target. `Package.swift` can be opened and run directly in Xcode
- Target: macOS 13+
- The decision logic for file operations (drop validation, collision detection, self-containment checks, depth guard) lives in `TabFilerCore`, which has no AppKit dependency and is unit-tested via `swift test`. UI concerns like `NSAlert` stay in the caller (`FileTreeView`); conflict resolution is passed in as a closure so the pure logic stays testable

## Tests

```sh
swift test
```

## Build & Run

```sh
swift build
swift run
```

Or open `Package.swift` in Xcode and run it.

## Roadmap

- App icon and `.app` packaging (for keeping it in the Dock)
