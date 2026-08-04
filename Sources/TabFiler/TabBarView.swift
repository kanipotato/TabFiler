import SwiftUI
import TabFilerCore

struct TabBarView: View {
    @ObservedObject var pane: PaneModel

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(pane.tabs) { tab in
                        TabChip(
                            tab: tab,
                            isSelected: tab.id == pane.selectedTabID,
                            onSelect: { pane.selectedTabID = tab.id },
                            onClose: { pane.closeTab(tab) }
                        )
                    }
                }
                .padding(.horizontal, 4)
            }
            Button(action: { pane.addTab() }) {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 6)
        }
        .padding(.vertical, 4)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct TabChip: View {
    @ObservedObject var tab: TabModel
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(tab.title)
                .lineLimit(1)
                .font(.system(size: 12))
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(6)
        .onTapGesture { onSelect() }
    }
}
