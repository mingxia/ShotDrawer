import CoreServices
import Darwin
import Foundation
import ImageIO

struct CandidateFile {
    let url: URL
    let observedAt: Date
}

enum ScreenshotCandidateReason: String, Equatable {
    case screenshotMetadata
    case screenshotFilenamePattern
    case recentlyCreated
    case pngImage
    case browserDownloadOrigin
    case unsupportedScreenshotFormat
    case insufficientEvidence
}

struct ScreenshotCandidateResult: Equatable {
    let isLikelyScreenshot: Bool
    let confidence: Double
    let reasons: [ScreenshotCandidateReason]
}

struct ScreenshotCandidateSignals {
    let creationDate: Date?
    let hasScreenshotMetadata: Bool
    let hasInternetOrigin: Bool
    let filenameMatchesScreenshotPattern: Bool
    let isPNG: Bool
}

struct ScreenshotCandidateClassifier {
    static let defaultThreshold = 0.55

    let threshold: Double

    init(threshold: Double = Self.defaultThreshold) {
        self.threshold = threshold
    }

    func classify(_ candidate: CandidateFile) -> ScreenshotCandidateResult {
        classify(signals(for: candidate.url), observedAt: candidate.observedAt)
    }

    func classify(_ signals: ScreenshotCandidateSignals, observedAt: Date) -> ScreenshotCandidateResult {
        var score = 0.0
        var reasons: [ScreenshotCandidateReason] = []

        if signals.hasScreenshotMetadata {
            score += 0.75
            reasons.append(.screenshotMetadata)
        }
        if signals.filenameMatchesScreenshotPattern {
            score += 0.30
            reasons.append(.screenshotFilenamePattern)
        }
        if let creationDate = signals.creationDate,
           abs(creationDate.timeIntervalSince(observedAt)) <= 10 {
            score += 0.25
            reasons.append(.recentlyCreated)
        }
        if signals.isPNG {
            score += 0.05
            reasons.append(.pngImage)
        } else {
            score -= 0.20
            reasons.append(.unsupportedScreenshotFormat)
        }
        if signals.hasInternetOrigin {
            score -= 0.85
            reasons.append(.browserDownloadOrigin)
        }

        let confidence = min(1, max(0, score))
        let likely = confidence >= threshold
        if !likely, reasons.isEmpty {
            reasons.append(.insufficientEvidence)
        }
        return ScreenshotCandidateResult(isLikelyScreenshot: likely, confidence: confidence, reasons: reasons)
    }

    private func signals(for url: URL) -> ScreenshotCandidateSignals {
        let values = try? url.resourceValues(forKeys: [.creationDateKey])
        let metadata = imageMetadata(at: url)
        let spotlightCapture = spotlightBoolean("kMDItemIsScreenCapture", at: url)
        let captureXattr = extendedAttribute(named: "com.apple.metadata:kMDItemIsScreenCapture", at: url)
        let whereFroms = extendedAttribute(named: "com.apple.metadata:kMDItemWhereFroms", at: url)

        return ScreenshotCandidateSignals(
            creationDate: values?.creationDate,
            hasScreenshotMetadata: spotlightCapture || captureXattr != nil || metadata,
            hasInternetOrigin: whereFroms != nil,
            filenameMatchesScreenshotPattern: Self.matchesDefaultScreenshotFilename(url.deletingPathExtension().lastPathComponent),
            isPNG: url.pathExtension.caseInsensitiveCompare("png") == .orderedSame
        )
    }

    /// Matches the locale-independent date/time shape in macOS' localized default name.
    /// The localized word for “Screenshot” is deliberately not required.
    static func matchesDefaultScreenshotFilename(_ stem: String) -> Bool {
        let pattern = #"\b\d{4}[-.]\d{1,2}[-.]\d{1,2}\b.*\b\d{1,2}[.:]\d{2}[.:]\d{2}\b"#
        return stem.range(of: pattern, options: .regularExpression) != nil
    }

    private func imageMetadata(at url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return false }

        // ImageIO does not expose a universal “is screenshot” property. Current native
        // captures can identify screencapture in the TIFF Software value; arbitrary
        // software values are not treated as evidence.
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let software = (tiff?[kCGImagePropertyTIFFSoftware] as? String)?.lowercased() ?? ""
        return software.contains("screencapture") || software.contains("screenshot")
    }

    private func spotlightBoolean(_ attribute: String, at url: URL) -> Bool {
        guard let item = MDItemCreate(kCFAllocatorDefault, url.path as CFString),
              let value = MDItemCopyAttribute(item, attribute as CFString)
        else { return false }
        return (value as? NSNumber)?.boolValue == true
    }

    private func extendedAttribute(named name: String, at url: URL) -> Data? {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return nil }
            let size = getxattr(path, name, nil, 0, 0, 0)
            guard size > 0 else { return nil }
            var data = Data(count: size)
            let read = data.withUnsafeMutableBytes { buffer in
                getxattr(path, name, buffer.baseAddress, size, 0, 0)
            }
            return read == size ? data : nil
        }
    }
}
