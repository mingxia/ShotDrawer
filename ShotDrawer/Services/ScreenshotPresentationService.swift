import Foundation

struct ScreenshotPresentation: Equatable {
    let typeName: String
    let systemImage: String
    let displayTitle: String
    let displaySubtitle: String?
}

struct ScreenshotPresentationService {
    func presentation(for item: ScreenshotItem) -> ScreenshotPresentation {
        let lines = meaningfulLines(item.ocrText)
        switch item.type {
        case .website:
            return ScreenshotPresentation(typeName: "Website", systemImage: "globe",
                displayTitle: item.detectedURLs.first?.host ?? lines.first ?? item.filename,
                displaySubtitle: lines.first(where: { $0 != item.detectedURLs.first?.absoluteString }))
        case .text:
            return ScreenshotPresentation(typeName: "Text", systemImage: "text.alignleft",
                displayTitle: lines.first ?? item.filename, displaySubtitle: lines.dropFirst().first)
        case .qrCode:
            let payload = item.detectedQRPayloads.first
            return ScreenshotPresentation(typeName: "QR Code", systemImage: "qrcode",
                displayTitle: item.detectedURLs.first?.host ?? payload ?? item.filename,
                displaySubtitle: item.detectedURLs.first == nil ? nil : payload)
        case .error:
            let errorLine = lines.first { ScreenshotClassifier.errorScore(in: $0) >= 0.25 }
            return ScreenshotPresentation(typeName: "Error", systemImage: "exclamationmark.triangle",
                displayTitle: errorLine ?? lines.first ?? item.filename, displaySubtitle: lines.first { $0 != errorLine })
        case .unknown:
            return ScreenshotPresentation(typeName: "Screenshot", systemImage: "photo",
                displayTitle: item.filename, displaySubtitle: nil)
        }
    }

    private func meaningfulLines(_ text: String?) -> [String] {
        (text ?? "").split(whereSeparator: \.isNewline).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { $0.count >= 2 }
    }
}
