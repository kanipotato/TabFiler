import Foundation

public final class FileNode: Identifiable {
    public let url: URL
    public let isDirectory: Bool
    public private(set) var loadedChildren: [FileNode]?
    public private(set) var isLoading = false

    public init(url: URL) {
        self.url = url
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        self.isDirectory = isDir.boolValue
    }

    public var id: String { url.path }
    public var name: String { url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent }

    /// 同期版。キャッシュ済みなら即返す。未読み込みならnilを返し、
    /// 呼び出し側はloadChildren(completion:)で非同期読み込みを開始すること。
    public var children: [FileNode]? {
        guard isDirectory else { return nil }
        return loadedChildren
    }

    /// ディレクトリ列挙はバックグラウンドスレッドで実行する。
    /// メインスレッドで同期的に行うと、ファイル数が多いフォルダ
    /// （Library, Pictures等）でUIがフリーズしXcodeにkillされるため。
    public func loadChildren(completion: @escaping () -> Void) {
        guard isDirectory, loadedChildren == nil, !isLoading else {
            completion()
            return
        }
        isLoading = true
        let targetURL = url
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: targetURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            let sorted = contents.sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
            let nodes = sorted.map { FileNode(url: $0) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.loadedChildren = nodes
                self.isLoading = false
                completion()
            }
        }
    }

    /// キャッシュ済みの子要素一覧を破棄する。次にchildren/loadChildrenが
    /// 呼ばれた際に再度ディスクから読み直される。
    /// ファイルのD&D移動/コピー後、内容が変わったフォルダの表示を
    /// 最新化するために呼ぶ。
    public func invalidateChildren() {
        loadedChildren = nil
    }

    /// 既に読み込み済み（=画面上で展開されたことがある）サブツリーだけを
    /// 対象に、指定URLに一致するノードを自分自身から再帰的に探す。
    /// 未読込のフォルダは展開されておらず表示に影響しないため探索しない。
    public func findLoadedNode(for targetURL: URL) -> FileNode? {
        if FileOperation.urlsPointToSamePath(url, targetURL) { return self }
        guard let loadedChildren else { return nil }
        for child in loadedChildren {
            if let found = child.findLoadedNode(for: targetURL) { return found }
        }
        return nil
    }
}
