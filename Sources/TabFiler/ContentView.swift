import SwiftUI

struct ContentView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        HSplitView {
            ForEach(appState.panes) { pane in
                PaneView(
                    pane: pane,
                    isActive: appState.panes.count > 1 && pane.id == appState.activePaneID,
                    canClosePane: appState.panes.count > 1,
                    onActivate: { appState.activePaneID = pane.id },
                    onSplit: { appState.splitPane() },
                    onClosePane: { appState.closePane(pane) }
                )
                .frame(minWidth: 280)
            }
        }
        .frame(minWidth: 480, minHeight: 360)
    }
}
