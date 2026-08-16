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
    }
}
