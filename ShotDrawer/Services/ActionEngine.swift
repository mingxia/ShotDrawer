import Foundation

struct ActionEngine {
    func actions(for item: ScreenshotItem, originalFileExists: Bool? = nil) -> [SuggestedAction] {
        let exists = originalFileExists ?? FileManager.default.fileExists(atPath: item.fileURL.path)
        var actions: [SuggestedAction] = []

        switch item.type {
        case .website:
            add(.openLink, "Open Link", "safari", 130, when: !item.detectedURLs.isEmpty, to: &actions)
            add(.copyText, "Copy Text", "doc.on.doc", 120, when: hasText(item), to: &actions)
            add(.archive, "Archive", "archivebox", 110, to: &actions)
            add(.copyLink, "Copy Link", "link", 80, when: !item.detectedURLs.isEmpty, to: &actions)
        case .text:
            add(.copyText, "Copy Text", "doc.on.doc", 130, when: hasText(item), to: &actions)
            add(.copyImage, "Copy Image", "photo.on.rectangle", 120, when: exists, to: &actions)
            add(.archive, "Archive", "archivebox", 110, to: &actions)
        case .qrCode:
            if !item.detectedURLs.isEmpty {
                add(.openLink, "Open Link", "safari", 130, to: &actions)
                add(.copyLink, "Copy Link", "link", 120, to: &actions)
            } else {
                add(.copyQRContent, "Copy QR Content", "qrcode", 130, when: !item.detectedQRPayloads.isEmpty, to: &actions)
                add(.copyImage, "Copy Image", "photo.on.rectangle", 120, when: exists, to: &actions)
            }
            add(.archive, "Archive", "archivebox", 110, to: &actions)
        case .error:
            add(.copyError, "Copy Error", "exclamationmark.triangle", 130, when: hasText(item), to: &actions)
            add(.copyImage, "Copy Image", "photo.on.rectangle", 120, when: exists, to: &actions)
            add(.archive, "Archive", "archivebox", 110, to: &actions)
        case .unknown:
            add(.copyImage, "Copy Image", "photo.on.rectangle", 130, when: exists, to: &actions)
            add(.showInFinder, "Show in Finder", "folder", 120, when: exists, to: &actions)
            add(.archive, "Archive", "archivebox", 110, to: &actions)
        }

        if item.workflowStatus == .archived {
            actions.removeAll { $0.kind == .archive }
            add(.restore, "Move to Inbox", "tray.and.arrow.down", 110, to: &actions)
        }
        add(.copyImage, "Copy Image", "photo.on.rectangle", 70, when: exists, to: &actions)
        add(.showInFinder, "Show in Finder", "folder", 60, when: exists, to: &actions)
        add(item.isFavorite ? .unfavorite : .favorite,
            item.isFavorite ? "Remove from Favorites" : "Add to Favorites",
            item.isFavorite ? "star.slash" : "star", 50, to: &actions)
        add(.delete, "Move to Trash", "trash", 10, role: .destructive, when: exists, to: &actions)

        var seen = Set<ActionKind>()
        return actions.filter { seen.insert($0.kind).inserted }.sorted { $0.priority > $1.priority }
    }

    private func hasText(_ item: ScreenshotItem) -> Bool { item.ocrText?.isEmpty == false }

    private func add(
        _ kind: ActionKind,
        _ title: String,
        _ image: String,
        _ priority: Int,
        role: SuggestedActionRole = .normal,
        when condition: Bool = true,
        to actions: inout [SuggestedAction]
    ) {
        guard condition else { return }
        actions.append(SuggestedAction(kind: kind, title: title, systemImage: image, priority: priority, role: role))
    }
}
