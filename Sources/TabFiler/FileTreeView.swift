import SwiftUI
import AppKit
import TabFilerCore

/// boundsDidChangeNotificationはタイミングによっては一度も発火しないことが
/// あるため、AppKitがレイアウト確定のたびに必ず呼ぶ`layout()`をフックして
/// カラム幅を合わせる。
final class SizingScrollView: NSScrollView {
    var onLayout: (() -> Void)?

    override func layout() {
        super.layout()
        onLayout?()
    }

    // 起動直後、ウィンドウの位置・サイズが復元される処理は通常のレイアウト
    // 経路を通らないことがあり、layout()が最終サイズで再度呼ばれない場合が
    // ある。ウィンドウが画面に表示・フォーカスされたタイミングで明示的に
    // もう一度レイアウトを強制する。
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(forceRelayout),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
    }

    @objc private func forceRelayout() {
        needsLayout = true
    }
}

/// NSOutlineViewを使ったディレクトリツリー表示。
/// SwiftUIのList/DisclosureGroupだと大量ファイルでの遅延展開や
/// 右クリックメニューの自由度が低いためAppKitを直接使う。
struct FileTreeView: NSViewRepresentable {
    @ObservedObject var tab: TabModel
    var onOpen: (URL) -> Void
    var onBackgroundDoubleClick: () -> Void
    /// D&Dでファイルが移動/コピーされた後、影響を受けたフォルダ
    /// （移動元の親・移動先）のURL集合を通知する。呼び出し側は
    /// AppState.refreshTabs(affectedBy:)に繋いで、同じフォルダを見ている
    /// 他のペイン・タブの表示も最新化する。
    var onFilesChanged: (Set<URL>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> SizingScrollView {
        let outlineView = NSOutlineView()
        outlineView.headerView = nil
        outlineView.style = .inset
        outlineView.usesAlternatingRowBackgroundColors = true
        outlineView.allowsMultipleSelection = true

        // D&D: ファイルURLの受け入れ登録（ペイン間・タブ間・Finderからの
        // ドロップに対応）。ドラッグ開始側はpasteboardWriterForItemの実装
        // だけで自動的に有効になる。
        outlineView.registerForDraggedTypes([.fileURL])
        outlineView.setDraggingSourceOperationMask([.move, .copy], forLocal: true)
        outlineView.setDraggingSourceOperationMask([.move, .copy], forLocal: false)

        let column = NSTableColumn(identifier: .init("name"))
        column.title = "Name"
        column.minWidth = 150
        column.maxWidth = 100000
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        // uniformだと、レイアウトパスでoutlineView幅が0付近の瞬間に列幅が
        // minWidthへスナップして巻き戻る現象があったため、最終列だけを
        // 残り幅へ伸ばすlastColumnOnlyにする。
        outlineView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        // デフォルトtrueだとアウトラインカラムを「中身の最大幅」に縮めてしまい、
        // ウィンドウ幅まで広がらず列がminWidth付近に巻き戻る。fillで埋めるため無効化。
        outlineView.autoresizesOutlineColumn = false

        outlineView.dataSource = context.coordinator
        outlineView.delegate = context.coordinator
        outlineView.target = context.coordinator
        outlineView.doubleAction = #selector(Coordinator.onDoubleClick(_:))
        outlineView.menu = context.coordinator.makeContextMenu()

        let scrollView = SizingScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        context.coordinator.outlineView = outlineView

        // reloadData()された内容の実際の構築(viewForの呼び出し)はAppKitに
        // よって次の描画サイクルまで遅延されることがある。フレーム幅が
        // まだ0(未確定)のうちにreloadData()してしまうと、その遅延実行が
        // 後から走った際にカラム幅が0時点の値へ巻き戻る問題があったため、
        // 列サイズ調整とデータ反映は「実寸のフレームが確定してから」
        // この一箇所(layout())だけで行う。
        var lastWidth: CGFloat = -1
        scrollView.onLayout = { [weak outlineView, weak scrollView] in
            guard let outlineView, let scrollView else { return }
            let width = scrollView.contentView.bounds.width
            guard width > 0, width != lastWidth else { return }
            lastWidth = width
            // sizeLastColumnToFitはoutlineView自身の幅の範囲で列を合わせるため、
            // まずoutlineView本体の幅をスクロールビューのコンテンツ幅に
            // 合わせないと、列幅(=セル幅)が狭いまま＝テキストが切れる。
            // 行の背景はNSTableRowViewが全幅で描くので一見正常に見えていた。
            if outlineView.frame.width != width {
                outlineView.setFrameSize(NSSize(width: width, height: outlineView.frame.height))
            }
            // sizeLastColumnToFit任せだと巻き戻ることがあったため列幅を明示。
            if let col = outlineView.tableColumns.first {
                col.width = width
            }
            outlineView.reloadData()
        }
        return scrollView
    }

    func updateNSView(_ nsView: SizingScrollView, context: Context) {
        context.coordinator.tab = tab
        context.coordinator.parent = self
        // まだ実寸のフレームが確定していない間はreloadDataしない。
        // 確定後はlayout()のonLayoutフックが拾って表示する。
        guard nsView.contentView.bounds.width > 0 else { return }
        context.coordinator.outlineView?.reloadData()
    }

    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        var parent: FileTreeView
        var tab: TabModel
        weak var outlineView: NSOutlineView?

        init(_ parent: FileTreeView) {
            self.parent = parent
            self.tab = parent.tab
        }

        func makeContextMenu() -> NSMenu {
            let menu = NSMenu()
            menu.addItem(withTitle: "開く", action: #selector(menuOpen(_:)), keyEquivalent: "")
            menu.addItem(withTitle: "Finderで表示", action: #selector(menuRevealInFinder(_:)), keyEquivalent: "")
            for item in menu.items { item.target = self }
            return menu
        }

        private func node(for item: Any?) -> FileNode {
            (item as? FileNode) ?? tab.rootNode
        }

        private var clickedNode: FileNode? {
            guard let outlineView else { return nil }
            let row = outlineView.clickedRow >= 0 ? outlineView.clickedRow : outlineView.selectedRow
            guard row >= 0 else { return nil }
            return outlineView.item(atRow: row) as? FileNode
        }

        @objc func menuOpen(_ sender: Any?) {
            guard let node = clickedNode else { return }
            parent.onOpen(node.url)
        }

        @objc func menuRevealInFinder(_ sender: Any?) {
            guard let node = clickedNode else { return }
            NSWorkspace.shared.activateFileViewerSelecting([node.url])
        }

        /// 本家Tablacus同様、アイコン/ファイル名の文字列以外の空白部分を
        /// ダブルクリックすると一つ上の階層へ戻る。
        @objc func onDoubleClick(_ sender: NSOutlineView) {
            guard let event = NSApp.currentEvent else { return }
            let point = sender.convert(event.locationInWindow, from: nil)
            let row = sender.row(at: point)
            guard row >= 0, let node = sender.item(atRow: row) as? FileNode else {
                parent.onBackgroundDoubleClick()
                return
            }
            // makeIfNecessary: false だとまだ生成されていない行でnilが返り、
            // 判定をスキップして無条件で開いてしまうため true にする。
            if let cellView = sender.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView,
               let textField = cellView.textField {
                let pointInCell = sender.convert(point, to: cellView)
                let contentWidth = textField.attributedStringValue.size().width
                let contentMinX = textField.frame.minX
                if pointInCell.x < contentMinX || pointInCell.x > contentMinX + contentWidth {
                    parent.onBackgroundDoubleClick()
                    return
                }
            }
            parent.onOpen(node.url)
        }

        /// 未読込のディレクトリはバックグラウンドで読み込みを開始し、
        /// 完了したら該当行だけreloadItemする。読込中はメインスレッドを
        /// ブロックしないよう、その場では0件として返す。
        private func triggerLoadIfNeeded(_ targetItem: Any?, _ n: FileNode) {
            guard n.isDirectory, n.children == nil, !n.isLoading else { return }
            n.loadChildren { [weak self] in
                self?.outlineView?.reloadItem(targetItem, reloadChildren: true)
            }
        }

        // MARK: NSOutlineViewDataSource

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            let n = node(for: item)
            triggerLoadIfNeeded(item, n)
            return n.children?.count ?? 0
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            node(for: item).children?[index] as Any
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            (item as? FileNode)?.isDirectory ?? false
        }

        // MARK: NSOutlineViewDelegate

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? FileNode else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("cell")
            let cell: NSTableCellView
            let textField: NSTextField
            if let reused = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView,
               let reusedField = reused.textField {
                cell = reused
                textField = reusedField
            } else {
                cell = NSTableCellView()
                cell.identifier = identifier
                textField = NSTextField(labelWithString: "")
                textField.translatesAutoresizingMaskIntoConstraints = false
                textField.usesSingleLineMode = true
                textField.maximumNumberOfLines = 1
                textField.lineBreakMode = .byTruncatingTail
                textField.cell?.truncatesLastVisibleLine = true
                textField.cell?.wraps = false
                textField.cell?.isScrollable = false
                cell.addSubview(textField)
                cell.textField = textField
                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                    textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                    textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                ])
            }

            let icon = NSWorkspace.shared.icon(forFile: node.url.path)
            icon.size = NSSize(width: 16, height: 16)
            let attachment = NSTextAttachment()
            attachment.image = icon
            attachment.bounds = CGRect(x: 0, y: -3, width: 16, height: 16)
            let result = NSMutableAttributedString(attachment: attachment)
            result.append(NSAttributedString(
                string: "  " + node.name,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 13),
                    .baselineOffset: 1
                ]
            ))
            textField.attributedStringValue = result
            return cell
        }

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

        /// 「以降すべてに適用」チェックの状態をこのドロップ操作内だけ
        /// メモリ上に保持するクロージャを作る。NSAlertはメインスレッド
        /// でしか出せないため、バックグラウンドスレッドから呼ばれた際は
        /// DispatchQueue.main.syncで待ち合わせる（execute自体は非同期に
        /// 呼ばれているのでデッドロックしない）。
        private func makeConflictResolver() -> (FileConflictInfo) -> ConflictResolution {
            var applyToAll = false
            var stickyResolution: ConflictResolution?
            return { [weak self] info in
                if applyToAll, let stickyResolution { return stickyResolution }
                guard let self else { return .cancel }

                var resolution: ConflictResolution = .cancel
                var checked = false
                let work = {
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = "「\(info.destination.lastPathComponent)」は既に存在します"
                    alert.informativeText = self.conflictDetailText(info)
                    let checkbox = NSButton(checkboxWithTitle: "以降すべてに適用", target: nil, action: nil)
                    checkbox.state = .off
                    alert.accessoryView = checkbox
                    alert.addButton(withTitle: "置換")
                    alert.addButton(withTitle: "両方残す")
                    alert.addButton(withTitle: "スキップ")
                    alert.addButton(withTitle: "キャンセル")
                    let response = alert.runModal()
                    switch response {
                    case .alertFirstButtonReturn: resolution = .replace
                    case .alertSecondButtonReturn: resolution = .keepBoth
                    case .alertThirdButtonReturn: resolution = .skip
                    default: resolution = .cancel
                    }
                    checked = checkbox.state == .on
                }
                if Thread.isMainThread {
                    work()
                } else {
                    DispatchQueue.main.sync(execute: work)
                }
                if checked {
                    applyToAll = true
                    stickyResolution = resolution
                }
                return resolution
            }
        }

        private func conflictDetailText(_ info: FileConflictInfo) -> String {
            """
            移動先: \(info.destination.deletingLastPathComponent().path)

            既存のファイル: \(formattedSize(info.existingSize)) ・ \(formattedDate(info.existingModified))
            移動元のファイル: \(formattedSize(info.incomingSize)) ・ \(formattedDate(info.incomingModified))
            """
        }

        private func formattedSize(_ size: Int64?) -> String {
            guard let size else { return "不明" }
            return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }

        private func formattedDate(_ date: Date?) -> String {
            guard let date else { return "不明" }
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }

        /// 50件を超える一括操作の安全弁。UIがブロックされうる大量操作の前に
        /// 一度だけ確認する。
        private func confirmLargeOperation(count: Int) -> Bool {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "\(count)件のファイルを操作します"
            alert.informativeText = "件数が多いため、完了まで少し時間がかかる場合があります。続けますか？"
            alert.addButton(withTitle: "続ける")
            alert.addButton(withTitle: "キャンセル")
            return alert.runModal() == .alertFirstButtonReturn
        }

        /// 移動/コピーの結果を報告する。ロールバックはしないため、
        /// 何件成功し、どこで・なぜ止まったかを必ず伝える。
        private func reportResult(_ result: FileOperationResult, kind: FileOperationKind, total: Int) {
            let verb = kind == .move ? "移動" : "コピー"

            if let failedURL = result.failedURL {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "\(verb)が途中で停止しました"
                alert.informativeText = "\(total)件中\(result.succeeded.count)件を\(verb)しました。"
                    + "「\(failedURL.lastPathComponent)」で止まりました"
                    + "（\(result.failureMessage ?? "不明なエラー")）。"
                alert.addButton(withTitle: "OK")
                alert.runModal()
                return
            }

            // キャンセル・全件成功・一部スキップのいずれも、失敗ではないため
            // Finder同様サイレントに終える（成功のたびにダイアログを出すと
            // かえって邪魔になるため）。
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
}
