import Foundation

struct ScreenshotItem: Identifiable, Equatable, Sendable {
    enum ItemType: String, Sendable { case unknown, website, text, qrCode, error }
    enum AnalysisStatus: String, Sendable { case pending, analyzing, ready, failed }
    enum WorkflowStatus: String, Sendable { case inbox, archived, deleted }

    let id: UUID
    let fileURL: URL
    let filename: String
    let createdAt: Date
    let importedAt: Date
    let width: Int
    let height: Int
    let fileSize: Int64
    let sourceApp: String?
    let sourceBundleID: String?
    var ocrText: String?
    var detectedURLs: [URL]
    var detectedQRPayloads: [String]
    var type: ItemType
    var confidence: Double
    var analysisStatus: AnalysisStatus
    var workflowStatus: WorkflowStatus
    var isFavorite: Bool
    var archivedAt: Date?
    var deletedAt: Date?
    var analysisVersion: Int
}
