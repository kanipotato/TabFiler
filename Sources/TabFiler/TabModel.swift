import Foundation
import Combine

final class TabModel: ObservableObject, Identifiable {
    let id = UUID()
    @Published private(set) var rootURL: URL
    @Published private(set) var rootNode: FileNode

    /// 訪問履歴。戻る/進むのためにルート変更のたびに記録する。
    private var history: [URL] = []
    private var historyIndex = 0

    init(rootURL: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.rootURL = rootURL
        self.rootNode = FileNode(url: rootURL)
        self.history = [rootURL]
    }

    var title: String { rootURL.lastPathComponent.isEmpty ? "/" : rootURL.lastPathComponent }
    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex < history.count - 1 }
    var canGoUp: Bool { rootURL.pathComponents.count > 1 }

    /// 新しい場所へ移動する（ツリー展開でのフォルダ選択など）。履歴に追加する。
    func navigate(to url: URL) {
        guard url != rootURL else { return }
        if historyIndex < history.count - 1 {
            history.removeSubrange((historyIndex + 1)...)
        }
        history.append(url)
        historyIndex = history.count - 1
        setRoot(url)
    }

    func goBack() {
        guard canGoBack else { return }
        historyIndex -= 1
        setRoot(history[historyIndex])
    }

    func goForward() {
        guard canGoForward else { return }
        historyIndex += 1
        setRoot(history[historyIndex])
    }

    func goUp() {
        guard canGoUp else { return }
        navigate(to: rootURL.deletingLastPathComponent())
    }

    private func setRoot(_ url: URL) {
        rootURL = url
        rootNode = FileNode(url: url)
    }
}

/// 1つのペイン（ウィンドウ分割された各領域）。本家Tablacus同様、
/// ペインごとに独立したタブ群を持つ。
final class PaneModel: ObservableObject, Identifiable {
    let id = UUID()
    @Published var tabs: [TabModel]
    @Published var selectedTabID: TabModel.ID

    init(rootURL: URL = FileManager.default.homeDirectoryForCurrentUser) {
        let first = TabModel(rootURL: rootURL)
        self.tabs = [first]
        self.selectedTabID = first.id
    }

    var selectedTab: TabModel? {
        tabs.first { $0.id == selectedTabID }
    }

    func addTab() {
        let newTab = TabModel(rootURL: selectedTab?.rootURL ?? FileManager.default.homeDirectoryForCurrentUser)
        tabs.append(newTab)
        selectedTabID = newTab.id
    }

    func closeTab(_ tab: TabModel) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabs.remove(at: index)
        if tabs.isEmpty {
            let newTab = TabModel()
            tabs = [newTab]
            selectedTabID = newTab.id
            return
        }
        if selectedTabID == tab.id {
            let newIndex = min(index, tabs.count - 1)
            selectedTabID = tabs[newIndex].id
        }
    }

    func closeSelectedTab() {
        guard let tab = selectedTab else { return }
        closeTab(tab)
    }
}

final class AppState: ObservableObject {
    @Published var panes: [PaneModel]
    @Published var activePaneID: PaneModel.ID

    init() {
        let first = PaneModel()
        self.panes = [first]
        self.activePaneID = first.id
    }

    var activePane: PaneModel? {
        panes.first { $0.id == activePaneID }
    }

    /// アクティブペインを複製する形で右側に新しいペインを追加する。
    func splitPane() {
        let rootURL = activePane?.selectedTab?.rootURL ?? FileManager.default.homeDirectoryForCurrentUser
        let newPane = PaneModel(rootURL: rootURL)
        panes.append(newPane)
        activePaneID = newPane.id
    }

    func closePane(_ pane: PaneModel) {
        guard panes.count > 1, let index = panes.firstIndex(where: { $0.id == pane.id }) else { return }
        panes.remove(at: index)
        if activePaneID == pane.id {
            let newIndex = min(index, panes.count - 1)
            activePaneID = panes[newIndex].id
        }
    }
}
