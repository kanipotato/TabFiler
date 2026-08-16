import AppKit
import TabFilerCore

// ツリー上のドラッグ&ドロップによるファイル移動・コピー。
//
// 元は`FileTreeView.Coordinator`本体に、DataSource/Delegateのセル描画・
// ダブルクリック処理・右クリックメニューと並んで直接書かれていた(508行)。
// D&Dは他の責務から参照されない独立した塊なので、extensionとしてこのファイルへ
// まとめた。ここで使うヘルパー(ドロップ先の逆引き・NSAlert提示など)も同居させてある。
//
// 判断ロジック(ドロップ可否・衝突解決の記憶・文言組み立て・報告要否)は
// AppKit非依存の`TabFilerCore`側にあり、単体テストで固定されている。
// このファイルが持つのはAppKitとの接続だけ。
extension FileTreeView.Coordinator {
    // MARK: - D&D (NSOutlineViewDataSource)

    /// ドラッグ開始。複数選択時は選択行それぞれについてAppKitが自動で
    /// このメソッドを呼び、ドラッグイメージへの枚数バッジ付与も含めて
    /// OS標準の見た目を使う（自作しない）。
    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let node = item as? FileNode else { return nil }
        return node.url as NSURL
    }

    /// ドロップ可否とハイライトを判定する。
    /// - フォルダ行の上ならそのフォルダを、ファイル行の上ならその親フォルダを
    ///   （NSOutlineViewのparent(forItem:)で逆引きして）ハイライトする。
    ///   ファイルがルート直下ならparentがnilになり、背景（ペイン全体）扱いになる。
    /// - 行間の挿入位置という概念は無い（名前順ソート固定のため）ので、
    ///   childIndexは常にNSOutlineViewDropOnItemIndexに丸める。
    func outlineView(
        _ outlineView: NSOutlineView,
        validateDrop info: NSDraggingInfo,
        proposedItem item: Any?,
        proposedChildIndex index: Int
    ) -> NSDragOperation {
        let sources = draggedFileURLs(from: info)
        guard !sources.isEmpty else { return [] }

        let destinationNode = dropDestinationNode(for: item, outlineView: outlineView)
        let destinationURL = destinationNode?.url ?? tab.rootURL

        let isWritable = FileManager.default.isWritableFile(atPath: destinationURL.path)
        let optionDown = NSEvent.modifierFlags.contains(.option)
        let kind = DropHandler.validate(
            sources: sources,
            destination: destinationURL,
            isWritable: isWritable,
            optionKeyDown: optionDown
        )

        guard kind != .none else { return [] }

        outlineView.setDropItem(destinationNode, dropChildIndex: NSOutlineViewDropOnItemIndex)
        return kind == .copy ? .copy : .move
    }

    /// 実際のファイル移動/コピーを実行する。UIをブロックしないよう
    /// バックグラウンドスレッドで行い、完了後にメインスレッドへ戻って
    /// ツリー更新と結果報告を行う。
    func outlineView(
        _ outlineView: NSOutlineView,
        acceptDrop info: NSDraggingInfo,
        item: Any?,
        childIndex index: Int
    ) -> Bool {
        let sources = draggedFileURLs(from: info)
        guard !sources.isEmpty else { return false }

        let destinationNode = dropDestinationNode(for: item, outlineView: outlineView)
        let destinationURL = destinationNode?.url ?? tab.rootURL

        // 実行直前にもう一度、移動先が存在するか確認する（ドロップ先が
        // ドラッグ操作中に消えていた場合はここで中止する）。
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: destinationURL.path, isDirectory: &isDir), isDir.boolValue else {
            presentAlert(message: "移動先のフォルダが見つかりませんでした。", informative: nil)
            return false
        }

        // フォルダを自分の子孫へドロップする最終防御。validateDropで
        // 弾いているはずだが、レースコンディション対策として
        // 実行直前にもう一度確認する（データ損失防止の最重要チェック）。
        for source in sources {
            if FileOperation.isDescendant(of: source, candidate: destinationURL) {
                presentAlert(message: "フォルダを自分自身または自分の中には移動できません。", informative: nil)
                return false
            }
        }

        if FileOperation.requiresLargeOperationConfirmation(fileCount: sources.count) {
            guard confirmLargeOperation(count: sources.count) else { return false }
        }

        let optionDown = NSEvent.modifierFlags.contains(.option)
        let kind: FileOperationKind = optionDown ? .copy : .move
        performOperation(sources: sources, destinationURL: destinationURL, kind: kind)
        return true
    }

    // MARK: - D&D ヘルパー

    private func draggedFileURLs(from info: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let objects = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]
        return objects ?? []
    }

    /// ドロップ先のフォルダを表すFileNodeを求める。
    /// - item がフォルダ行なら、その行自身
    /// - item がファイル行なら、その親（NSOutlineViewのparent(forItem:)で逆引き。
    ///   ルート直下のファイルならparentはnilになり、背景＝ルート扱いになる）
    /// - item が nil（背景）なら nil（呼び出し側でtab.rootURLとして扱う）
    private func dropDestinationNode(for item: Any?, outlineView: NSOutlineView) -> FileNode? {
        guard let fileNode = item as? FileNode else { return nil }
        if fileNode.isDirectory {
            return fileNode
        }
        return outlineView.parent(forItem: fileNode) as? FileNode
    }

    private func performOperation(sources: [URL], destinationURL: URL, kind: FileOperationKind) {
        let affected = Set(sources.map { $0.deletingLastPathComponent().standardizedFileURL } + [destinationURL.standardizedFileURL])
        let total = sources.count
        let resolveConflict = makeConflictResolver()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = FileOperation.execute(
                sources: sources,
                destinationFolder: destinationURL,
                kind: kind,
                resolveConflict: resolveConflict
            )
            DispatchQueue.main.async {
                guard let self else { return }
                self.parent.onFilesChanged(affected)
                self.reportResult(result, kind: kind, total: total)
            }
        }
    }

    /// 「以降すべてに適用」チェックの状態をこのドロップ操作内だけ保持する解決器を作る。
    /// 記憶の仕組み自体は`StickyConflictResolver`（Core層・テスト済み）が持ち、
    /// ここはNSAlertを出して答えを返す部分だけを担当する。
    ///
    /// NSAlertはメインスレッドでしか出せないため、バックグラウンドスレッドから
    /// 呼ばれた際は`DispatchQueue.main.sync`で待ち合わせる（`execute`自体は非同期に
    /// 呼ばれているのでデッドロックしない）。
    private func makeConflictResolver() -> (FileConflictInfo) -> ConflictResolution {
        StickyConflictResolver { info in
            var answer = ConflictAnswer(resolution: .cancel, applyToAll: false)
            let work = {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = OperationMessages.conflictTitle(for: info)
                alert.informativeText = OperationMessages.conflictDetail(for: info)
                let checkbox = NSButton(checkboxWithTitle: "以降すべてに適用", target: nil, action: nil)
                checkbox.state = .off
                alert.accessoryView = checkbox
                alert.addButton(withTitle: "置換")
                alert.addButton(withTitle: "両方残す")
                alert.addButton(withTitle: "スキップ")
                alert.addButton(withTitle: "キャンセル")
                let response = alert.runModal()
                let resolution: ConflictResolution
                switch response {
                case .alertFirstButtonReturn: resolution = .replace
                case .alertSecondButtonReturn: resolution = .keepBoth
                case .alertThirdButtonReturn: resolution = .skip
                default: resolution = .cancel
                }
                answer = ConflictAnswer(resolution: resolution, applyToAll: checkbox.state == .on)
            }
            if Thread.isMainThread {
                work()
            } else {
                DispatchQueue.main.sync(execute: work)
            }
            return answer
        }
        .asClosure()
    }

    /// 50件を超える一括操作の安全弁。UIがブロックされうる大量操作の前に
    /// 一度だけ確認する。
    private func confirmLargeOperation(count: Int) -> Bool {
        let text = OperationMessages.largeOperationConfirmation(count: count)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = text.title
        alert.informativeText = text.body
        alert.addButton(withTitle: "続ける")
        alert.addButton(withTitle: "キャンセル")
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// 移動/コピーの結果を報告する。何を報告し何を黙って終えるかの判断は
    /// `OperationMessages.resultReport`（Core層・テスト済み）が持つ。
    private func reportResult(_ result: FileOperationResult, kind: FileOperationKind, total: Int) {
        guard let report = OperationMessages.resultReport(result, kind: kind, total: total) else { return }
        presentAlert(message: report.title, informative: report.body)
    }

    private func presentAlert(message: String, informative: String?) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        if let informative { alert.informativeText = informative }
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
