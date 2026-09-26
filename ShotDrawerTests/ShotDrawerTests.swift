import XCTest
@testable import ShotDrawer

final class ShotDrawerTests: XCTestCase {
    private func repository() throws -> ScreenshotRepository {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        return try ScreenshotRepository(databaseURL: url)
    }

    private func item(url: URL = URL(fileURLWithPath: "/tmp/screenshot.png")) -> ScreenshotItem {
        ScreenshotItem(
            id: UUID(), fileURL: url, filename: url.lastPathComponent, createdAt: Date(timeIntervalSince1970: 1),
            importedAt: Date(timeIntervalSince1970: 2), width: 100, height: 80, fileSize: 42,
            sourceApp: nil, sourceBundleID: nil, ocrText: nil, detectedURLs: [], detectedQRPayloads: [],
            type: .unknown, confidence: 1, analysisStatus: .pending, workflowStatus: .inbox, isFavorite: false,
            archivedAt: nil, deletedAt: nil, analysisVersion: 0
        )
    }

    func testDatabaseInsertAndRead() async throws {
        let repository = try repository()
        let expected = item()
        XCTAssertTrue(try await repository.insert(expected))
        let items = try await repository.fetchAll()
        XCTAssertEqual(items, [expected])
    }

    func testDuplicateFileURLIsNotInserted() async throws {
        let repository = try repository()
        XCTAssertTrue(try await repository.insert(item()))
        XCTAssertFalse(try await repository.insert(item()))
        XCTAssertEqual(try await repository.fetchAll().count, 1)
    }

    func testStatusPersists() async throws {
        let repository = try repository()
        let expected = item()
        _ = try await repository.insert(expected)
        try await repository.updateAnalysisStatus(id: expected.id, status: .failed)
        XCTAssertEqual(try await repository.fetchAll().first?.analysisStatus, .failed)
    }

    func testClassificationAnalysisPersists() async throws {
        let repository = try repository()
        let expected = item()
        _ = try await repository.insert(expected)
        let url = URL(string: "https://example.com")!
        try await repository.updateAnalysis(
            id: expected.id,
            text: "Example",
            urls: [url],
            qrPayloads: [url.absoluteString],
            type: .qrCode,
            confidence: 0.98,
            status: .ready,
            version: ScreenshotAnalyzer.analysisVersion
        )
        let actual = try await repository.fetchAll().first
        XCTAssertEqual(actual?.ocrText, "Example")
        XCTAssertEqual(actual?.detectedURLs, [url])
        XCTAssertEqual(actual?.detectedQRPayloads, [url.absoluteString])
        XCTAssertEqual(actual?.type, .qrCode)
        XCTAssertEqual(actual?.confidence, 0.98)
        XCTAssertEqual(actual?.analysisVersion, ScreenshotAnalyzer.analysisVersion)
    }

    func testURLExtractionFiltersAndDeduplicates() {
        let urls = ScreenshotAnalyzer.extractURLs(from: "See https://example.com/a and https://example.com/a, not ftp://example.com")
        XCTAssertEqual(urls.map(\.absoluteString), ["https://example.com/a"])
    }

    func testPlainTextClassification() {
        XCTAssertEqual(classify(text: "This is enough meaningful text to classify").type, .text)
    }

    func testURLClassification() {
        XCTAssertEqual(classify(text: "Visit our site", urls: [URL(string: "https://example.com")!]).type, .website)
    }

    func testQRURLClassificationHasPriority() {
        XCTAssertEqual(classify(
            text: "fatal error traceback", urls: [URL(string: "https://example.com")!], qr: ["https://example.com"]
        ).type, .qrCode)
    }

    func testStackTraceClassification() {
        XCTAssertEqual(classify(text: "Exception: request failed\nStack trace:\nmain.swift:12").type, .error)
    }

    func testWarningAloneIsNotAnError() {
        XCTAssertEqual(classify(text: "Warning: remember to save your document before closing").type, .text)
    }

    func testImageWithoutOCRClassification() {
        XCTAssertEqual(classify().type, .unknown)
    }

    func testQRURLBecomesActionableURL() {
        XCTAssertEqual(ScreenshotAnalyzer.actionableURL(from: " https://example.com/path ")?.absoluteString, "https://example.com/path")
        XCTAssertNil(ScreenshotAnalyzer.actionableURL(from: "plain QR content"))
    }

    func testWebsitePrimaryActions() {
        var value = item(); value.type = .website
        value.ocrText = "Website text"; value.detectedURLs = [URL(string: "https://example.com")!]
        XCTAssertEqual(primaryActions(value), [.openLink, .copyText, .archive])
    }

    func testTextPrimaryActions() {
        var value = item(); value.type = .text; value.ocrText = "Enough text"
        XCTAssertEqual(primaryActions(value), [.copyText, .copyImage, .archive])
    }

    func testQRPrimaryActionsAdaptToPayload() {
        var value = item(); value.type = .qrCode; value.detectedQRPayloads = ["hello"]
        XCTAssertEqual(primaryActions(value), [.copyQRContent, .copyImage, .archive])
        value.detectedURLs = [URL(string: "https://example.com")!]
        XCTAssertEqual(primaryActions(value), [.openLink, .copyLink, .archive])
    }

    func testErrorAndUnknownPrimaryActions() {
        var value = item(); value.type = .error; value.ocrText = "fatal error"
        XCTAssertEqual(primaryActions(value), [.copyError, .copyImage, .archive])
        value.type = .unknown
        XCTAssertEqual(primaryActions(value), [.copyImage, .showInFinder, .archive])
    }

    func testMissingOriginalRemovesFileActions() {
        let kinds = ActionEngine().actions(for: item(), originalFileExists: false).map(\.kind)
        XCTAssertFalse(kinds.contains(.copyImage)); XCTAssertFalse(kinds.contains(.showInFinder))
        XCTAssertFalse(kinds.contains(.delete)); XCTAssertTrue(kinds.contains(.archive))
    }

    func testArchiveRestoreAndFavoriteAreIndependent() async throws {
        let repository = try repository(); let expected = item()
        _ = try await repository.insert(expected)
        try await repository.setFavorite(id: expected.id, isFavorite: true)
        try await repository.setWorkflow(id: expected.id, status: .archived, at: now)
        var actual = try await repository.fetchAll().first
        XCTAssertEqual(actual?.workflowStatus, .archived); XCTAssertTrue(actual?.isFavorite == true)
        XCTAssertEqual(actual?.analysisStatus, .pending)
        try await repository.setWorkflow(id: expected.id, status: .inbox, at: nil)
        actual = try await repository.fetchAll().first
        XCTAssertEqual(actual?.workflowStatus, .inbox); XCTAssertNil(actual?.archivedAt)
        XCTAssertTrue(actual?.isFavorite == true)
    }

    func testArchiveAllOnlyChangesWorkflow() async throws {
        let repository = try repository(); let expected = item()
        _ = try await repository.insert(expected)
        try await repository.archiveInbox(at: now)
        let actual = try await repository.fetchAll().first
        XCTAssertEqual(actual?.workflowStatus, .archived)
        XCTAssertEqual(actual?.analysisStatus, expected.analysisStatus)
    }

    func testV1DatabaseMigratesAnalysisAndWorkflowIndependently() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("sqlite")
        do {
            let database = try SQLiteDatabase(url: url)
            try database.execute("""
            CREATE TABLE screenshots (
              id TEXT PRIMARY KEY, file_url TEXT NOT NULL UNIQUE, filename TEXT NOT NULL,
              created_at REAL NOT NULL, imported_at REAL NOT NULL, width INTEGER NOT NULL, height INTEGER NOT NULL,
              file_size INTEGER NOT NULL, source_app TEXT, source_bundle_id TEXT, ocr_text TEXT,
              detected_urls TEXT NOT NULL DEFAULT '[]', detected_qr_payloads TEXT NOT NULL DEFAULT '[]',
              type TEXT NOT NULL, confidence REAL NOT NULL, status TEXT NOT NULL, is_favorite INTEGER NOT NULL DEFAULT 0,
              archived_at REAL, deleted_at REAL, analysis_version INTEGER NOT NULL DEFAULT 0);
            INSERT INTO screenshots VALUES ('00000000-0000-0000-0000-000000000001','/tmp/old.png','old.png',1,2,10,10,20,NULL,NULL,NULL,'[]','[]','unknown',0.5,'archived',1,3,NULL,1);
            PRAGMA user_version=1;
            """)
        }
        let repository = try ScreenshotRepository(databaseURL: url)
        let migrated = try await repository.fetchAll().first
        XCTAssertEqual(migrated?.workflowStatus, .archived)
        XCTAssertEqual(migrated?.analysisStatus, .ready)
        XCTAssertTrue(migrated?.isFavorite == true)
    }

    @MainActor
    func testFailedTrashDoesNotChangeWorkflow() async throws {
        struct ExpectedFailure: Error {}
        let repository = try repository()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        try Data([0]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let expected = item(url: file); _ = try await repository.insert(expected)
        let executor = ActionExecutor(repository: repository, trashOperation: { _ in throw ExpectedFailure() })
        let action = SuggestedAction(kind: .delete, title: "Move to Trash", systemImage: "trash", priority: 1, role: .destructive)
        do { _ = try await executor.execute(action, for: expected); XCTFail("Expected trash failure") }
        catch is ExpectedFailure {}
        XCTAssertEqual(try await repository.fetchAll().first?.workflowStatus, .inbox)
    }

    func testScreenshotExtensionsAreCaseInsensitive() {
        for name in ["one.png", "two.JPG", "three.jpeg", "four.HEIC"] {
            XCTAssertTrue(ScreenshotFolderWatcher.supports(URL(fileURLWithPath: name)))
        }
        for name in ["image.gif", "notes.txt", "png"] {
            XCTAssertFalse(ScreenshotFolderWatcher.supports(URL(fileURLWithPath: name)))
        }
    }

    func testNativeScreenshotMetadataIsStrongEvidence() {
        let result = candidateClassifier.classify(signals(
            nameMatches: false, screenshotMetadata: true, internetOrigin: false, isPNG: true
        ), observedAt: now)
        XCTAssertTrue(result.isLikelyScreenshot)
        XCTAssertTrue(result.reasons.contains(.screenshotMetadata))
    }

    func testBrowserDownloadPNGIsIgnoredEvenWhenRecentAndNamedLikeScreenshot() {
        let result = candidateClassifier.classify(signals(
            nameMatches: true, screenshotMetadata: false, internetOrigin: true, isPNG: true
        ), observedAt: now)
        XCTAssertFalse(result.isLikelyScreenshot)
        XCTAssertTrue(result.reasons.contains(.browserDownloadOrigin))
    }

    func testCopiedJPGIsIgnored() {
        let result = candidateClassifier.classify(signals(
            nameMatches: false, screenshotMetadata: false, internetOrigin: false, isPNG: false
        ), observedAt: now)
        XCTAssertFalse(result.isLikelyScreenshot)
    }

    func testLocalizedScreenshotFilenameIsRecognizedWithoutEnglishPrefix() {
        XCTAssertTrue(ScreenshotCandidateClassifier.matchesDefaultScreenshotFilename("截屏 2026-09-25 10.32.18"))
        let result = candidateClassifier.classify(signals(
            nameMatches: true, screenshotMetadata: false, internetOrigin: false, isPNG: true
        ), observedAt: now)
        XCTAssertTrue(result.isLikelyScreenshot)
    }

    func testFilenameAloneIsNotEnough() {
        var candidate = signals(nameMatches: true, screenshotMetadata: false, internetOrigin: false, isPNG: true)
        candidate = ScreenshotCandidateSignals(
            creationDate: now.addingTimeInterval(-120),
            hasScreenshotMetadata: candidate.hasScreenshotMetadata,
            hasInternetOrigin: candidate.hasInternetOrigin,
            filenameMatchesScreenshotPattern: candidate.filenameMatchesScreenshotPattern,
            isPNG: candidate.isPNG
        )
        XCTAssertFalse(candidateClassifier.classify(candidate, observedAt: now).isLikelyScreenshot)
    }

    private var candidateClassifier: ScreenshotCandidateClassifier { ScreenshotCandidateClassifier() }
    private var now: Date { Date(timeIntervalSince1970: 1_000) }

    private func signals(
        nameMatches: Bool,
        screenshotMetadata: Bool,
        internetOrigin: Bool,
        isPNG: Bool
    ) -> ScreenshotCandidateSignals {
        ScreenshotCandidateSignals(
            creationDate: now,
            hasScreenshotMetadata: screenshotMetadata,
            hasInternetOrigin: internetOrigin,
            filenameMatchesScreenshotPattern: nameMatches,
            isPNG: isPNG
        )
    }

    private func classify(text: String = "", urls: [URL] = [], qr: [String] = []) -> ScreenshotClassification {
        ScreenshotClassifier().classify(ocrText: text, detectedURLs: urls, detectedQRPayloads: qr)
    }

    private func primaryActions(_ item: ScreenshotItem) -> [ActionKind] {
        ActionEngine().actions(for: item, originalFileExists: true).filter(\.isPrimary).prefix(3).map(\.kind)
    }
}
