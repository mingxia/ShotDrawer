import SwiftUI

struct MainWindow: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $appState.selection)
        } content: {
            InboxView(destination: appState.selection ?? .inbox)
        } detail: {
            if let item = appState.selectedScreenshot {
                ScreenshotDetailView(item: item)
            } else {
                DetailPlaceholder()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .task { appState.offerFolderSelectionIfNeeded() }
    }
}

private struct DetailPlaceholder: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No Screenshot Selected")
                .font(.title3.weight(.semibold))
            Text("Select a screenshot to see its details and quick actions.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(minWidth: 260)
    }
}
