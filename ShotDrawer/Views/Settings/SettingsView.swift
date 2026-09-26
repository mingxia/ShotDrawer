import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch ShotDrawer at login", isOn: Binding(
                    get: { appState.launchAtLogin },
                    set: { appState.setLaunchAtLogin($0) }
                ))
                Toggle("Show floating card after screenshot", isOn: $appState.showFloatingCard)
                Toggle("Show Inbox count in menu bar", isOn: $appState.showInboxCount)
            }

            Section("Screenshots") {
                LabeledContent("Screenshot folder") {
                    HStack {
                        Text(appState.folderAccess.displayPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button(appState.folderAccess.folderURL == nil ? "Choose…" : "Change…") {
                            appState.chooseScreenshotFolder()
                        }
                    }
                }
            }

            Section("Analysis") {
                Toggle("Extract text from screenshots", isOn: $appState.extractText)
                Toggle("Detect links", isOn: $appState.detectLinks)
                    .disabled(!appState.extractText)
                    .help(appState.extractText ? "Detect web links in extracted text" : "Turn on text extraction to detect links")
                Toggle("Detect QR codes", isOn: $appState.detectQRCodes)
            }

            Section("Privacy") {
                Label("Screenshot analysis happens on this Mac.", systemImage: "lock.shield")
                Text("ShotDrawer does not upload your screenshots.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}
