import Foundation

/// 移動かコピーか。
public enum FileOperationKind: Equatable {
    case move
    case copy
}

/// 同名衝突が起きたときにユーザー（呼び出し側）が選ぶ解決方法。
public enum ConflictResolution: Equatable {
    case skip
    case keepBoth
    case replace
    case cancel
}

/// 同名衝突ダイアログに出す情報一式（移動先パス・両ファイルのサイズと日付）。
public struct FileConflictInfo: Equatable {
    public let source: URL
    public let destination: URL
    public let existingSize: Int64?
    public let existingModified: Date?
    public let incomingSize: Int64?
    public let incomingModified: Date?

    public init(
        source: URL,
        destination: URL,
        existingSize: Int64?,
        existingModified: Date?,
        incomingSize: Int64?,
        incomingModified: Date?
    ) {
        self.source = source
        self.destination = destination
        self.existingSize = existingSize
        self.existingModified = existingModified
        self.incomingSize = incomingSize
        self.incomingModified = incomingModified
    }
}

/// コピー先のディレクトリ階層が異常に深くなったため安全側に倒して中断した
/// ことを表すエラー。`isDescendant`の事前チェックをすり抜けた場合の
/// 多重防御として`FileOperation.copyItemWithDepthGuard`が投げる。
public struct CopyDepthLimitExceededError: LocalizedError, Equatable {
    public let path: String
    public let limit: Int

    public var errorDescription: String? {
        "コピー先のディレクトリ階層が深くなりすぎたため中断しました（上限\(limit)階層）。シンボリックリンク経由で自分自身の中へコピーしようとしていないか確認してください: \(path)"
    }
}

/// 実行結果。ロールバックはしないため、「どこまで成功したか」「どこで
/// 止まったか」を呼び出し側が正確に報告できるよう詳細に持つ。
public struct FileOperationResult: Equatable {
    /// 実際に移動/コピーできたファイル（元のURL）。
    public var succeeded: [URL] = []
    /// スキップされたファイル（消えていた／衝突時にスキップ選択／既に同じ場所だった）。
    public var skipped: [URL] = []
    /// 失敗して処理を止めた対象。nilなら失敗せず終了（全件完了 or キャンセル）。
    public var failedURL: URL?
    /// 失敗理由（NSErrorのlocalizedDescriptionそのまま等）。
    public var failureMessage: String?
    /// ユーザーが衝突ダイアログで「キャンセル」を選んで途中終了したかどうか。
    public var cancelled: Bool = false

    public init(
        succeeded: [URL] = [],
        skipped: [URL] = [],
        failedURL: URL? = nil,
        failureMessage: String? = nil,
        cancelled: Bool = false
    ) {
        self.succeeded = succeeded
        self.skipped = skipped
        self.failedURL = failedURL
        self.failureMessage = failureMessage
        self.cancelled = cancelled
    }
}

/// ファイルの移動・コピーを実行する、UIに依存しない純粋なロジック。
/// NSAlert等は一切扱わない。衝突時の判断は`resolveConflict`クロージャに
/// 委ねることでテスト可能にしている（呼び出し側でNSAlertを出す想定）。
public enum FileOperation {
    /// この件数を超える一括操作は、実行前にユーザーへ確認を取ることを推奨する
    /// 安全弁のしきい値。大量ファイルの移動でUIがブロックされるのを防ぐため。
    public static let largeOperationThreshold = 50

    public static func requiresLargeOperationConfirmation(fileCount: Int) -> Bool {
        fileCount > largeOperationThreshold
    }

    /// 2つのURLが同じ場所を指しているかを、パス文字列で比較する。
    /// `URL`同士の`==`は、片方がディレクトリ扱い（末尾に"/"が付く
    /// `hasDirectoryPath == true`）でもう片方がそうでない場合に、
    /// 中身が同じパスでも一致しないことがあるため（`NSOutlineView`から
    /// 渡ってくるURLや`contentsOfDirectory`が返すURLはディレクトリだと
    /// 末尾"/"付きになる等）、必ずこちらを使う。
    public static func urlsPointToSamePath(_ a: URL, _ b: URL) -> Bool {
        a.standardizedFileURL.path == b.standardizedFileURL.path
    }

    /// destinationがsource自身、またはsourceの子孫（配下）かどうか。
    /// フォルダを自分自身の中にドロップする操作を検出するために使う。
    ///
    /// 比較の前に両方のパスを`resolvingSymlinksInPath()`で実体パスへ解決してから
    /// 文字列比較する。シンボリックリンク経由（例: 「Aを指すリンク」をAの中や
    /// 別の場所からAへドロップする）で自己内包チェックを迂回できてしまう問題への
    /// 対策（詳細は`SymlinkDescendantBypassTests`を参照）。
    /// なお`resolvingSymlinksInPath()`は対象が実在しない場合そのままのパスを返す
    /// ため、存在しないパスでも従来どおり文字列プレフィックス比較として機能する。
    public static func isDescendant(of source: URL, candidate: URL) -> Bool {
        let sourcePath = source.resolvingSymlinksInPath().standardizedFileURL.path
        let candidatePath = candidate.resolvingSymlinksInPath().standardizedFileURL.path
        if candidatePath == sourcePath { return true }
        let sourcePrefix = sourcePath.hasSuffix("/") ? sourcePath : sourcePath + "/"
        return candidatePath.hasPrefix(sourcePrefix)
    }

    /// 同名衝突時、Finder同様「name 2.ext」形式で空いている名前を探す。
    /// 呼び出し側は既に`originalName`が衝突していることを確認済みである前提。
    public static func uniqueNameForConflict(
        originalName: String,
        in folder: URL,
        fileManager: FileManager = .default
    ) -> String {
        let ext = (originalName as NSString).pathExtension
        let base: String
        if ext.isEmpty {
            base = originalName
        } else {
            base = String(originalName.dropLast(ext.count + 1))
        }
        var counter = 2
        while true {
            let candidateName = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            let candidateURL = folder.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateName
            }
            counter += 1
        }
    }

    /// 複数ファイルの移動/コピーを1件ずつ実行する。
    ///
    /// 実行前チェック（全て通ってから開始、1件でも違反があれば何もせず終了）:
    /// - destinationFolderがsourcesのいずれかの子孫（または同一）ならフォルダの
    ///   自己内包になるため全体を拒否する
    /// - destinationFolder自体が存在しなければ拒否する
    ///
    /// 実行中（1件ずつ、途中失敗したらロールバックせずそこで止める）:
    /// - ドラッグ元が消えていたらその1件だけスキップして続行
    /// - destinationFolder == source の親（＝既にそこにある）ならその1件だけ
    ///   スキップして続行（Finder同様、何もしない）
    /// - 同名衝突があれば`resolveConflict`に判断を委ねる
    ///   （.cancelなら即座に打ち切り、以降は一切手をつけない）
    /// - move/copyが例外を投げたら、その1件で処理を止めて結果に理由を残す。
    ///   `FileManager.moveItem`はアトミックなので、そのファイルは移動元・移動先
    ///   どちらか一方に必ず存在する状態が保たれる（中途半端な状態にはならない）
    public static func execute(
        sources: [URL],
        destinationFolder: URL,
        kind: FileOperationKind,
        fileManager: FileManager = .default,
        resolveConflict: (FileConflictInfo) -> ConflictResolution
    ) -> FileOperationResult {
        var result = FileOperationResult()

        // フォルダを自分自身の中に入れる操作は、1件でも該当したら
        // ドロップ全体を拒否する（部分実行はしない）。
        for source in sources {
            if isDescendant(of: source, candidate: destinationFolder) {
                result.failedURL = source
                result.failureMessage = "「\(source.lastPathComponent)」を自分自身または自分の中のフォルダには移動できません。"
                return result
            }
        }

        guard fileManager.fileExists(atPath: destinationFolder.path) else {
            result.failedURL = destinationFolder
            result.failureMessage = "移動先のフォルダが見つかりません。"
            return result
        }

        for source in sources {
            guard fileManager.fileExists(atPath: source.path) else {
                result.skipped.append(source)
                continue
            }

            if urlsPointToSamePath(source.deletingLastPathComponent(), destinationFolder) {
                // 既に同じ場所にある。何もしない。
                result.skipped.append(source)
                continue
            }

            var destination = destinationFolder.appendingPathComponent(source.lastPathComponent)
            if fileManager.fileExists(atPath: destination.path) {
                let info = conflictInfo(source: source, destination: destination, fileManager: fileManager)
                switch resolveConflict(info) {
                case .skip:
                    result.skipped.append(source)
                    continue
                case .cancel:
                    result.cancelled = true
                    return result
                case .keepBoth:
                    let newName = uniqueNameForConflict(originalName: source.lastPathComponent, in: destinationFolder, fileManager: fileManager)
                    destination = destinationFolder.appendingPathComponent(newName)
                case .replace:
                    do {
                        try fileManager.removeItem(at: destination)
                    } catch {
                        result.failedURL = source
                        result.failureMessage = error.localizedDescription
                        return result
                    }
                }
            }

            do {
                switch kind {
                case .move:
                    try fileManager.moveItem(at: source, to: destination)
                case .copy:
                    try copyItemWithDepthGuard(at: source, to: destination, fileManager: fileManager)
                }
                result.succeeded.append(source)
            } catch {
                result.failedURL = source
                result.failureMessage = error.localizedDescription
                return result
            }
        }

        return result
    }

    /// コピー先ディレクトリ階層がこの深さを超えたら異常事態とみなして中断する
    /// 安全弁。主防御は`isDescendant`のシンボリックリンク解決による事前拒否だが、
    /// 万一それをすり抜けるケース（未知の迂回経路や将来の変更によるリグレッション）
    /// があっても、`FileManager.copyItem`が自分自身の中へ無制限に再帰コピーして
    /// PATH_MAXに達するまでディスクを汚し続ける実害を防ぐための多重防御。
    /// 通常の利用でここまで深いディレクトリ構造は考えにくい値として設定している。
    public static let maxCopyDepth = 200

    /// コピー時にディレクトリ階層が異常に深くならないよう見張りながら再帰的に
    /// コピーする。`FileManager.copyItem`をディレクトリに対して1回呼ぶと、
    /// その内部で無制限に再帰する（シンボリックリンク経由で自分自身の中へ
    /// コピーするような異常系に入ると、対策なしではディスクを埋め尽くすか
    /// PATH_MAXに達するまで止まらない）。
    ///
    /// ここでは自前でディレクトリを1階層ずつ辿り、深さが`maxCopyDepth`を
    /// 超えたら安全側に倒して中断する。ファイル・シンボリックリンクは
    /// （それ自体が新たな再帰の起点にならないため）`FileManager.copyItem`に
    /// そのまま1件コピーさせる。シンボリックリンクは辿らずリンクとして
    /// コピーする（`copyItem`のデフォルト挙動と同じ）。
    private static func copyItemWithDepthGuard(
        at source: URL,
        to destination: URL,
        fileManager: FileManager,
        depth: Int = 0
    ) throws {
        let resourceValues = try source.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        let isSymlink = resourceValues.isSymbolicLink ?? false
        let isDirectory = resourceValues.isDirectory ?? false

        guard isDirectory, !isSymlink else {
            // ファイル、またはシンボリックリンク（ディレクトリを指していても
            // 辿らずリンクのままコピーする）。単発のコピーなので再帰は起きない。
            try fileManager.copyItem(at: source, to: destination)
            return
        }

        if depth >= maxCopyDepth {
            throw CopyDepthLimitExceededError(path: destination.path, limit: maxCopyDepth)
        }

        // attributesには権限（パーミッション）のみを引き継ぐ。
        // attributesOfItemが返す辞書をそのまま渡すと、createDirectoryが
        // 解釈しないキー（ファイル種別等）まで含まれてしまうため絞り込む。
        var directoryAttributes: [FileAttributeKey: Any] = [:]
        if let permissions = (try? fileManager.attributesOfItem(atPath: source.path))?[.posixPermissions] {
            directoryAttributes[.posixPermissions] = permissions
        }
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: false, attributes: directoryAttributes)

        let children = try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil, options: [])
        for child in children {
            try copyItemWithDepthGuard(
                at: child,
                to: destination.appendingPathComponent(child.lastPathComponent),
                fileManager: fileManager,
                depth: depth + 1
            )
        }
    }

    private static func conflictInfo(source: URL, destination: URL, fileManager: FileManager) -> FileConflictInfo {
        let existingAttrs = try? fileManager.attributesOfItem(atPath: destination.path)
        let incomingAttrs = try? fileManager.attributesOfItem(atPath: source.path)
        return FileConflictInfo(
            source: source,
            destination: destination,
            existingSize: (existingAttrs?[.size] as? NSNumber)?.int64Value,
            existingModified: existingAttrs?[.modificationDate] as? Date,
            incomingSize: (incomingAttrs?[.size] as? NSNumber)?.int64Value,
            incomingModified: incomingAttrs?[.modificationDate] as? Date
        )
    }
}
