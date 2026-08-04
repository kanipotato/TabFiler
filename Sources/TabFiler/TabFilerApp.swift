import SwiftUI
import AppKit
import TabFilerCore

/// SwiftPM実行ファイルにはアプリバンドルがなく、放置すると
/// activationPolicyが正しく設定されずウィンドウが前面に出ないため、
/// 明示的にDockアプリとして有効化する。
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct TabFilerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("新しいタブ") {
                    appState.activePane?.addTab()
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("タブを閉じる") {
                    appState.activePane?.closeSelectedTab()
                }
                .keyboardShortcut("w", modifiers: .command)

                Divider()

                Button("右に分割") {
                    appState.splitPane()
                }
                .keyboardShortcut("d", modifiers: .command)

                Button("ペインを閉じる") {
                    if let pane = appState.activePane {
                        appState.closePane(pane)
                    }
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
            }

            CommandGroup(after: .toolbar) {
                Button("戻る") {
                    appState.activePane?.selectedTab?.goBack()
                }
                .keyboardShortcut("[", modifiers: .command)

                Button("進む") {
                    appState.activePane?.selectedTab?.goForward()
                }
                .keyboardShortcut("]", modifiers: .command)

                Button("上の階層へ") {
                    appState.activePane?.selectedTab?.goUp()
                }
                .keyboardShortcut(.upArrow, modifiers: .command)
            }
        }
    }
}
