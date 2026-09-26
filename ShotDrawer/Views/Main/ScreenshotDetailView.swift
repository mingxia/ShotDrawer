import AppKit
import SwiftUI

struct ScreenshotDetailView: View {
    let item: ScreenshotItem
    @EnvironmentObject private var appState: AppState
    @State private var confirmsTrash = false

    private var presentation: ScreenshotPresentation { appState.presentationService.presentation(for: item) }
    private var originalExists: Bool { FileManager.default.fileExists(atPath: item.fileURL.path) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(nsImage: NSImage(contentsOf: item.fileURL)
                    ?? NSImage(contentsOf: appState.thumbnailService.url(for: item.id)) ?? NSImage())
                    .resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 10))
                HStack {
                    Label(presentation.typeName, systemImage: presentation.systemImage).font(.headline)
                    Spacer(); Text(item.createdAt, style: .relative).foregroundStyle(.secondary)
                }
                Text(presentation.displayTitle).font(.title3.weight(.semibold))
                if let subtitle = presentation.displaySubtitle { Text(subtitle).foregroundStyle(.secondary) }
                if !originalExists {
                    Label("Original file unavailable", systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                }
                LabeledContent("Size", value: "\(item.width) × \(item.height)")
                Divider()
                Text("Extracted Text").font(.headline)
                if let text = item.ocrText, !text.isEmpty {
                    Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(item.analysisStatus == .analyzing ? "Extracting text…" : "No text was detected.")
                        .foregroundStyle(.secondary)
                }
                if !item.detectedURLs.isEmpty {
                    Divider()
                    Text("Links").font(.headline)
                    ForEach(item.detectedURLs, id: \.absoluteString) { url in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(url.absoluteString).textSelection(.enabled).lineLimit(2)
                        }
                    }
                }
                if !item.detectedQRPayloads.isEmpty {
                    Divider(); Text("Detected QR Content").font(.headline)
                    ForEach(item.detectedQRPayloads, id: \.self) { Text($0).textSelection(.enabled) }
                }
                Divider()
                Text("Quick Actions").font(.headline)
                HStack {
                    ForEach(appState.actionEngine.actions(for: item, originalFileExists: originalExists)) { action in
                        Button(action.title, systemImage: action.systemImage) {
                            if action.kind == .delete { confirmsTrash = true }
                            else { Task { await appState.perform(action, for: item) } }
                        }
                    }
                }.buttonStyle(.bordered)
            }
            .padding(20)
        }
        .frame(minWidth: 260)
        .confirmationDialog("Move this screenshot to Trash?", isPresented: $confirmsTrash) {
            Button("Move to Trash", role: .destructive) {
                if let action = appState.actionEngine.actions(for: item).first(where: { $0.kind == .delete }) {
                    Task { await appState.perform(action, for: item) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The original screenshot will be moved to the Trash.")
        }
    }
}
