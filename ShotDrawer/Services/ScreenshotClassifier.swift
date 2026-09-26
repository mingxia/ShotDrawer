import Foundation

struct ScreenshotClassification: Equatable {
    let type: ScreenshotItem.ItemType
    let confidence: Double
}

struct ScreenshotClassifier {
    func classify(
        ocrText: String,
        detectedURLs: [URL],
        detectedQRPayloads: [String]
    ) -> ScreenshotClassification {
        if !detectedQRPayloads.isEmpty {
            return ScreenshotClassification(type: .qrCode, confidence: 0.98)
        }

        let errorScore = Self.errorScore(in: ocrText)
        if errorScore >= 0.70 {
            return ScreenshotClassification(type: .error, confidence: errorScore)
        }

        if !detectedURLs.isEmpty {
            return ScreenshotClassification(type: .website, confidence: 0.82)
        }

        let meaningfulCharacters = ocrText.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        }.count
        if meaningfulCharacters >= 12 {
            return ScreenshotClassification(
                type: .text,
                confidence: min(0.85, 0.55 + Double(meaningfulCharacters - 12) / 100)
            )
        }

        return ScreenshotClassification(type: .unknown, confidence: meaningfulCharacters == 0 ? 1 : 0.65)
    }

    static func errorScore(in text: String) -> Double {
        let normalized = text.lowercased()
        var score = 0.0

        if normalized.contains("traceback") { score += 0.85 }
        if normalized.contains("stack trace") { score += 0.70 }
        if normalized.contains("uncaught") { score += 0.55 }
        if normalized.contains("exception") { score += 0.50 }
        if normalized.contains("fatal") { score += 0.50 }
        if normalized.contains("failed") || normalized.contains("failure") { score += 0.35 }
        if normalized.contains("error") { score += 0.25 }
        if normalized.contains("status code") { score += 0.35 }
        if normalized.contains("warning") { score += 0.15 }

        let httpErrorPattern = #"\b(?:http\s*)?[45]\d{2}\b"#
        if normalized.range(of: httpErrorPattern, options: .regularExpression) != nil {
            score += 0.75
        }
        return min(1, score)
    }
}
