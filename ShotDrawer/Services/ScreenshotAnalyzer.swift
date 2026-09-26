import Foundation

struct ScreenshotAnalyzer {
    static let analysisVersion = 2

    private let repository: ScreenshotRepository
    private let ocr: OCRService
    private let barcode: BarcodeService
    private let classifier: ScreenshotClassifier

    init(
        repository: ScreenshotRepository,
        ocr: OCRService = OCRService(),
        barcode: BarcodeService = BarcodeService(),
        classifier: ScreenshotClassifier = ScreenshotClassifier()
    ) {
        self.repository = repository
        self.ocr = ocr
        self.barcode = barcode
        self.classifier = classifier
    }

    func analyze(_ item: ScreenshotItem, options: AnalysisOptions = .allEnabled) async {
        do {
            if item.analysisStatus == .ready, item.analysisVersion == Self.analysisVersion { return }
            try await repository.updateAnalysisStatus(id: item.id, status: .analyzing)
            async let textResult = options.extractText
                ? capture { try await ocr.recognizeText(in: item.fileURL) }
                : AnalysisResult(value: "", isSuccess: true)
            async let qrResult = options.detectQRCodes
                ? capture { try await barcode.detectQRPayloads(in: item.fileURL) }
                : AnalysisResult(value: [String](), isSuccess: true)
            let (resolvedText, resolvedQR) = await (textResult, qrResult)
            guard resolvedText.isSuccess || resolvedQR.isSuccess else {
                throw AnalysisError.allRequestsFailed
            }

            let text = resolvedText.value ?? ""
            let qrPayloads = resolvedQR.value ?? []
            let textURLs = options.detectLinks && options.extractText ? Self.extractURLs(from: text) : []
            let qrURLs = qrPayloads.compactMap(Self.actionableURL(from:))
            let urls = Self.deduplicated(textURLs + qrURLs)
            let classification = classifier.classify(
                ocrText: text, detectedURLs: urls, detectedQRPayloads: qrPayloads
            )
            try await repository.updateAnalysis(
                id: item.id,
                text: text,
                urls: urls,
                qrPayloads: qrPayloads,
                type: classification.type,
                confidence: classification.confidence,
                status: .ready,
                version: Self.analysisVersion
            )
            AppLogger.analysis.info("Local analysis completed for \(item.filename, privacy: .public)")
        } catch {
            AppLogger.analysis.error("Local analysis failed for \(item.filename, privacy: .public): \(error.localizedDescription, privacy: .public)")
            do { try await repository.updateAnalysisStatus(id: item.id, status: .failed) } catch {
                AppLogger.database.error("Unable to persist analysis failure: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    static func extractURLs(from text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var seen = Set<String>()
        return detector.matches(in: text, options: [], range: range).compactMap { match in
            guard let url = match.url, let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
                  seen.insert(url.absoluteString).inserted else { return nil }
            return url
        }
    }

    static func actionableURL(from payload: String) -> URL? {
        guard let url = URL(string: payload.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host != nil
        else { return nil }
        return url
    }

    private static func deduplicated(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.absoluteString).inserted }
    }

    private func capture<T>(_ operation: () async throws -> T) async -> AnalysisResult<T> {
        do { return AnalysisResult(value: try await operation(), isSuccess: true) }
        catch { return AnalysisResult(value: nil, isSuccess: false) }
    }
}

struct AnalysisOptions: Sendable {
    let extractText: Bool
    let detectLinks: Bool
    let detectQRCodes: Bool

    static let allEnabled = AnalysisOptions(extractText: true, detectLinks: true, detectQRCodes: true)
}

private struct AnalysisResult<Value> {
    let value: Value?
    let isSuccess: Bool
}

private enum AnalysisError: Error {
    case allRequestsFailed
}
