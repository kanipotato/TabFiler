import Foundation

final class FileNode: Identifiable {
    let url: URL
    let isDirectory: Bool
    private(set) var loadedChildren: [FileNode]?
    private(set) var isLoading = false

    init(url: URL) {
        self.url = url
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        self.isDirectory = isDir.boolValue
    }

    var id: String { url.path }
    var name: String { url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent }

    /// 同期版。キャッシュ済みなら即返す。未読み込みならnilを返し、
    /// 呼び出し側はloadChildren(completion:)で非同期読み込みを開始すること。
    var children: [FileNode]? {
        guard isDirectory else { return nil }
        return loadedChildren
    }

    /// ディレクトリ列挙はバックグラウンドスレッドで実行する。
    /// メインスレッドで同期的に行うと、ファイル数が多いフォルダ
    /// （Library, Pictures等）でUIがフリーズしXcodeにkillされるため。
    func loadChildren(completion: @escaping () -> Void) {
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
}
