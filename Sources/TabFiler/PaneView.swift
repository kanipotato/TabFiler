import SwiftUI

/// 1ペイン分のUI（タブバー＋ナビゲーションバー＋ファイルツリー）。
/// 複数ペインをHSplitViewで並べる。
struct PaneView: View {
    @ObservedObject var pane: PaneModel
    var isActive: Bool
    var canClosePane: Bool
    var onActivate: () -> Void
    var onSplit: () -> Void
    var onClosePane: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TabBarView(pane: pane)
            Divider()
            if let tab = pane.selectedTab {
                NavigationBarView(
                    tab: tab,
                    canClosePane: canClosePane,
                    onSplit: onSplit,
                    onClosePane: onClosePane
                )
                Divider()
                FileTreeView(
                    tab: tab,
                    onOpen: { url in open(url, in: tab) },
                    onBackgroundDoubleClick: { tab.goUp() }
                )
                .id(tab.id)
            }
        }
        // アクティブペインを左端の細い帯で示す。クリックでアクティブ化。
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(isActive ? Color.accentColor : Color.clear)
                .frame(width: 2)
        }
        .contentShape(Rectangle())
        .onTapGesture { onActivate() }
    }

    private func open(_ url: URL, in tab: TabModel) {
        let values = try? url.resourceValues(forKeys: [.isPackageKey, .isDirectoryKey])
        let isPackage = values?.isPackage ?? false
        let isDir = values?.isDirectory ?? false
        // ③ .appなどのパッケージはダブルクリックで起動。通常ディレクトリのみ階層を掘る。
        if isPackage {
            NSWorkspace.shared.open(url)
        } else if isDir {
            tab.navigate(to: url)
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}
