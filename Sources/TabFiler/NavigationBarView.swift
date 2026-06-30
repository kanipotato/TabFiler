import SwiftUI
import AppKit

struct NavigationBarView: View {
    @ObservedObject var tab: TabModel
    var canClosePane: Bool
    var onSplit: () -> Void
    var onClosePane: () -> Void

    @State private var copied = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: { tab.goBack() }) {
                Image(systemName: "chevron.left")
            }
            .disabled(!tab.canGoBack)

            Button(action: { tab.goForward() }) {
                Image(systemName: "chevron.right")
            }
            .disabled(!tab.canGoForward)

            Button(action: { tab.goUp() }) {
                Image(systemName: "chevron.up")
            }
            .disabled(!tab.canGoUp)

            Text(tab.rootURL.path)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)

            // ① 表示中のフルパスをクリップボードへコピー
            Button(action: copyPath) {
                Image(systemName: copied ? "checkmark" : "doc.on.clipboard")
            }
            .help("フルパスをコピー")

            Spacer()

            // ② ウィンドウ分割（ペイン追加／このペインを閉じる）
            Button(action: onSplit) {
                Image(systemName: "rectangle.split.2x1")
            }
            .help("右に分割")

            if canClosePane {
                Button(action: onClosePane) {
                    Image(systemName: "rectangle.righthalf.inset.filled.arrow.right")
                }
                .help("このペインを閉じる")
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func copyPath() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(tab.rootURL.path, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
    }
}
