import XCTest
@testable import TabFilerCore

final class ModelTests: XCTestCase {
    var tempDir: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        tempDir = fm.temporaryDirectory.appendingPathComponent("TabFilerModelTests-\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        // macOSでは/var -> /private/varのシンボリックリンクがあり、
        // FileManager.temporaryDirectoryは非解決のパスを返す一方、
        // contentsOfDirectory等は解決済みパスを返すため、ここで揃えておく。
        tempDir = tempDir.resolvingSymlinksInPath()
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: tempDir)
    }

    private func loadChildrenSync(_ node: FileNode) {
        let exp = expectation(description: "load")
        node.loadChildren { exp.fulfill() }
        wait(for: [exp], timeout: 2)
    }

    // MARK: - FileNode

    func testInvalidateChildrenForcesReload() throws {
        try "x".write(to: tempDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let node = FileNode(url: tempDir)
        loadChildrenSync(node)
        XCTAssertEqual(node.children?.count, 1)

        try "y".write(to: tempDir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        // invalidateしない限りキャッシュのままなので件数は変わらない。
        XCTAssertEqual(node.children?.count, 1)

        node.invalidateChildren()
        XCTAssertNil(node.children, "invalidate直後は未読込状態(nil)に戻る")

        loadChildrenSync(node)
        XCTAssertEqual(node.children?.count, 2)
    }

    func testFindLoadedNodeOnlySearchesLoadedSubtree() throws {
        let subDir = tempDir.appendingPathComponent("sub")
        try fm.createDirectory(at: subDir, withIntermediateDirectories: true)
        let deepDir = subDir.appendingPathComponent("deep")
        try fm.createDirectory(at: deepDir, withIntermediateDirectories: true)

        let root = FileNode(url: tempDir)
        loadChildrenSync(root)
        // subはまだ展開(loadChildren)していないので、その配下のdeepは見つからない。
        XCTAssertNil(root.findLoadedNode(for: deepDir))

        guard let subNode = root.children?.first(where: { FileOperation.urlsPointToSamePath($0.url, subDir) }) else {
            return XCTFail("subノードが見つからない")
        }
        loadChildrenSync(subNode)

        XCTAssertNotNil(root.findLoadedNode(for: deepDir), "subを展開した後ならdeepが見つかる")
        XCTAssertTrue(FileOperation.urlsPointToSamePath(root.findLoadedNode(for: subDir)?.url ?? URL(fileURLWithPath: "/"), subDir))
        XCTAssertTrue(FileOperation.urlsPointToSamePath(root.findLoadedNode(for: tempDir)?.url ?? URL(fileURLWithPath: "/"), tempDir), "自分自身も見つかる")
    }

    // MARK: - TabModel

    func testTabModelReloadRebuildsRootNode() throws {
        try "x".write(to: tempDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let tab = TabModel(rootURL: tempDir)
        loadChildrenSync(tab.rootNode)
        XCTAssertEqual(tab.rootNode.children?.count, 1)

        try "y".write(to: tempDir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        tab.reload()
        XCTAssertNil(tab.rootNode.children, "作り直された直後は未読込")

        loadChildrenSync(tab.rootNode)
        XCTAssertEqual(tab.rootNode.children?.count, 2)
    }

    // MARK: - AppState.refreshTabs（別ペイン/別タブの同期更新）

    func testRefreshTabsReloadsTabWhoseRootMatches() throws {
        let appState = AppState()
        guard let pane = appState.activePane else { return XCTFail("ペインが無い") }
        let tab = TabModel(rootURL: tempDir)
        pane.tabs = [tab]
        pane.selectedTabID = tab.id
        loadChildrenSync(tab.rootNode)
        let originalRootNode = tab.rootNode

        appState.refreshTabs(affectedBy: [tempDir])

        XCTAssertFalse(tab.rootNode === originalRootNode, "ルート一致タブはreload()でrootNodeが作り直される")
    }

    func testRefreshTabsInvalidatesLoadedNestedNodeWithoutReloadingRoot() throws {
        let subDir = tempDir.appendingPathComponent("sub")
        try fm.createDirectory(at: subDir, withIntermediateDirectories: true)

        let appState = AppState()
        guard let pane = appState.activePane else { return XCTFail("ペインが無い") }
        let tab = TabModel(rootURL: tempDir)
        pane.tabs = [tab]
        pane.selectedTabID = tab.id
        loadChildrenSync(tab.rootNode)
        guard let subNode = tab.rootNode.children?.first(where: { FileOperation.urlsPointToSamePath($0.url, subDir) }) else {
            return XCTFail("subノードが見つからない")
        }
        loadChildrenSync(subNode)
        XCTAssertNotNil(subNode.children)

        let originalRootNode = tab.rootNode
        appState.refreshTabs(affectedBy: [subDir])

        XCTAssertTrue(tab.rootNode === originalRootNode, "ルート自体は変わらない（展開状態が保たれる）")
        XCTAssertNil(subNode.children, "影響を受けたネストしたノードだけinvalidateされる")
    }

    func testRefreshTabsDoesNothingForUnrelatedTabs() throws {
        let otherDir = tempDir.appendingPathComponent("unrelated")
        try fm.createDirectory(at: otherDir, withIntermediateDirectories: true)

        let appState = AppState()
        guard let pane = appState.activePane else { return XCTFail("ペインが無い") }
        let tab = TabModel(rootURL: otherDir)
        pane.tabs = [tab]
        pane.selectedTabID = tab.id
        loadChildrenSync(tab.rootNode)
        let originalRootNode = tab.rootNode

        appState.refreshTabs(affectedBy: [tempDir.appendingPathComponent("somewhere-else")])

        XCTAssertTrue(tab.rootNode === originalRootNode, "無関係なタブは変化しない")
    }

    func testRefreshTabsUpdatesAllMatchingPanesAndTabs() throws {
        // 「別ペインが同じフォルダを見ている」ケース: 複数ペイン・複数タブに
        // またがって同じフォルダをルートにしているものが全部更新されること。
        let appState = AppState()
        guard let firstPane = appState.activePane else { return XCTFail("ペインが無い") }
        let tabA = TabModel(rootURL: tempDir)
        firstPane.tabs = [tabA]
        firstPane.selectedTabID = tabA.id

        appState.splitPane()
        guard appState.panes.count == 2 else { return XCTFail("ペイン分割に失敗") }
        let secondPane = appState.panes[1]
        let tabB = TabModel(rootURL: tempDir)
        secondPane.tabs = [tabB]
        secondPane.selectedTabID = tabB.id

        loadChildrenSync(tabA.rootNode)
        loadChildrenSync(tabB.rootNode)
        let originalA = tabA.rootNode
        let originalB = tabB.rootNode

        appState.refreshTabs(affectedBy: [tempDir])

        XCTAssertFalse(tabA.rootNode === originalA)
        XCTAssertFalse(tabB.rootNode === originalB)
    }
}
