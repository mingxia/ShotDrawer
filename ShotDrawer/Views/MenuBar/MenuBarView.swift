import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("ShotDrawer")
                    .font(.headline)
                Text(appState.attentionSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            if recentItems.isEmpty {
                Label("No recent screenshots", systemImage: "photo.on.rectangle")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                Text("Recent").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(recentItems) { item in
                    Button { appState.openScreenshot(item) } label: {
                        HStack(spacing: 10) {
                            if let image = NSImage(contentsOf: appState.thumbnailService.url(for: item.id)) {
                                Image(nsImage: image).resizable().scaledToFill().frame(width: 38, height: 30).clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            let presentation = appState.presentationService.presentation(for: item)
                            Label(presentation.typeName, systemImage: presentation.systemImage)
                            Spacer()
                            Text(item.createdAt, style: .relative).foregroundStyle(.secondary)
                        }
                    }.buttonStyle(.plain)
                }
            }

            Divider()

            Button("Open Inbox", systemImage: "tray") {
                appState.openMainWindow()
            }
            .keyboardShortcut("o")

            Button("Quick Settings…", systemImage: "gearshape") {
                appState.openSettings()
            }

            Divider()

            Button("Quit ShotDrawer") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(16)
        .frame(width: 300)
    }

    private var recentItems: [ScreenshotItem] { Array(appState.screenshots.prefix(3)) }
}
