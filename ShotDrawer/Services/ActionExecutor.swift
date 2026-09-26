import AppKit
import Foundation

enum ActionExecutionResult: Equatable { case completed, copied, dismissed }

@MainActor
final class ActionExecutor {
    private let repository: ScreenshotRepository
    private let trashOperation: (URL) throws -> Void

    init(repository: ScreenshotRepository, trashOperation: @escaping (URL) throws -> Void = { url in
        _ = try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }) {
        self.repository = repository
        self.trashOperation = trashOperation
    }

    func execute(_ action: SuggestedAction, for item: ScreenshotItem) async throws -> ActionExecutionResult {
        switch action.kind {
        case .openLink:
            guard let url = item.detectedURLs.first else { return .dismissed }
            NSWorkspace.shared.open(url)
            return .completed
        case .copyLink:
            guard let value = item.detectedURLs.first?.absoluteString else { return .dismissed }
            copy(value); return .copied
        case .copyText, .copyError:
            guard let value = item.ocrText, !value.isEmpty else { return .dismissed }
            copy(value); return .copied
        case .copyQRContent:
            guard let value = item.detectedQRPayloads.first else { return .dismissed }
            copy(value); return .copied
        case .copyImage:
            guard let image = NSImage(contentsOf: item.fileURL) else { return .dismissed }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
            return .copied
        case .showInFinder:
            guard FileManager.default.fileExists(atPath: item.fileURL.path) else { return .dismissed }
            NSWorkspace.shared.activateFileViewerSelecting([item.fileURL]); return .completed
        case .favorite:
            try await repository.setFavorite(id: item.id, isFavorite: true); return .completed
        case .unfavorite:
            try await repository.setFavorite(id: item.id, isFavorite: false); return .completed
        case .archive:
            try await repository.setWorkflow(id: item.id, status: .archived, at: Date()); return .completed
        case .restore:
            try await repository.setWorkflow(id: item.id, status: .inbox, at: nil); return .completed
        case .delete:
            guard FileManager.default.fileExists(atPath: item.fileURL.path) else { return .dismissed }
            try trashOperation(item.fileURL)
            try await repository.setWorkflow(id: item.id, status: .deleted, at: Date())
            return .completed
        }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
