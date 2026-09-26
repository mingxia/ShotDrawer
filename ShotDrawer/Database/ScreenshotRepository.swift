import Foundation
import SQLite3

actor ScreenshotRepository {
    private let database: SQLiteDatabase

    init(databaseURL: URL) throws {
        database = try SQLiteDatabase(url: databaseURL)
        try migrate()
    }

    @discardableResult
    func insert(_ item: ScreenshotItem) throws -> Bool {
        let sql = """
        INSERT OR IGNORE INTO screenshots
        (id, file_url, filename, created_at, imported_at, width, height, file_size,
         source_app, source_bundle_id, ocr_text, detected_urls, detected_qr_payloads,
         type, confidence, analysis_status, workflow_status, is_favorite, archived_at, deleted_at, analysis_version)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        let statement = try database.prepare(sql)
        defer { sqlite3_finalize(statement) }
        bind(item, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.statement(String(cString: sqlite3_errmsg(database.handle)))
        }
        return sqlite3_changes(database.handle) == 1
    }

    func fetchAll() throws -> [ScreenshotItem] {
        let statement = try database.prepare("""
        SELECT id, file_url, filename, created_at, imported_at, width, height, file_size,
               source_app, source_bundle_id, ocr_text, detected_urls, detected_qr_payloads,
               type, confidence, analysis_status, workflow_status, is_favorite,
               archived_at, deleted_at, analysis_version
        FROM screenshots WHERE workflow_status != 'deleted' ORDER BY created_at DESC;
        """)
        defer { sqlite3_finalize(statement) }
        var items: [ScreenshotItem] = []
        while sqlite3_step(statement) == SQLITE_ROW { items.append(decode(statement)) }
        return items
    }

    func updateAnalysis(
        id: UUID,
        text: String,
        urls: [URL],
        qrPayloads: [String],
        type: ScreenshotItem.ItemType,
        confidence: Double,
        status: ScreenshotItem.AnalysisStatus,
        version: Int
    ) throws {
        let statement = try database.prepare("UPDATE screenshots SET ocr_text=?, detected_urls=?, detected_qr_payloads=?, type=?, confidence=?, analysis_status=?, analysis_version=? WHERE id=?;")
        defer { sqlite3_finalize(statement) }
        bindText(text, at: 1, in: statement)
        bindText(encode(urls.map(\.absoluteString)), at: 2, in: statement)
        bindText(encode(qrPayloads), at: 3, in: statement)
        bindText(type.rawValue, at: 4, in: statement)
        sqlite3_bind_double(statement, 5, confidence)
        bindText(status.rawValue, at: 6, in: statement)
        sqlite3_bind_int(statement, 7, Int32(version))
        bindText(id.uuidString, at: 8, in: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw DatabaseError.statement(String(cString: sqlite3_errmsg(database.handle))) }
    }

    func updateAnalysisStatus(id: UUID, status: ScreenshotItem.AnalysisStatus) throws {
        let statement = try database.prepare("UPDATE screenshots SET analysis_status=? WHERE id=?;")
        defer { sqlite3_finalize(statement) }
        bindText(status.rawValue, at: 1, in: statement)
        bindText(id.uuidString, at: 2, in: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw DatabaseError.statement(String(cString: sqlite3_errmsg(database.handle))) }
    }

    func setFavorite(id: UUID, isFavorite: Bool) throws {
        let statement = try database.prepare("UPDATE screenshots SET is_favorite=? WHERE id=?;")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, isFavorite ? 1 : 0)
        bindText(id.uuidString, at: 2, in: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw DatabaseError.statement(String(cString: sqlite3_errmsg(database.handle))) }
    }

    func setWorkflow(id: UUID, status: ScreenshotItem.WorkflowStatus, at date: Date?) throws {
        let sql: String
        switch status {
        case .inbox: sql = "UPDATE screenshots SET workflow_status=?, archived_at=NULL, deleted_at=NULL WHERE id=?;"
        case .archived: sql = "UPDATE screenshots SET workflow_status=?, archived_at=?, deleted_at=NULL WHERE id=?;"
        case .deleted: sql = "UPDATE screenshots SET workflow_status=?, deleted_at=? WHERE id=?;"
        }
        let statement = try database.prepare(sql)
        defer { sqlite3_finalize(statement) }
        bindText(status.rawValue, at: 1, in: statement)
        if status == .inbox {
            bindText(id.uuidString, at: 2, in: statement)
        } else {
            bindDate(date, at: 2, in: statement)
            bindText(id.uuidString, at: 3, in: statement)
        }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw DatabaseError.statement(String(cString: sqlite3_errmsg(database.handle))) }
    }

    func archiveInbox(at date: Date) throws {
        let statement = try database.prepare("UPDATE screenshots SET workflow_status='archived', archived_at=? WHERE workflow_status='inbox';")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, date.timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw DatabaseError.statement(String(cString: sqlite3_errmsg(database.handle))) }
    }

    private func bind(_ item: ScreenshotItem, to statement: OpaquePointer) {
        let text: [(Int32, String?)] = [
            (1, item.id.uuidString), (2, item.fileURL.standardizedFileURL.path), (3, item.filename),
            (9, item.sourceApp), (10, item.sourceBundleID), (11, item.ocrText),
            (12, encode(item.detectedURLs.map(\.absoluteString))), (13, encode(item.detectedQRPayloads)),
            (14, item.type.rawValue), (16, item.analysisStatus.rawValue), (17, item.workflowStatus.rawValue)
        ]
        text.forEach { bindText($0.1, at: $0.0, in: statement) }
        sqlite3_bind_double(statement, 4, item.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 5, item.importedAt.timeIntervalSince1970)
        sqlite3_bind_int(statement, 6, Int32(item.width)); sqlite3_bind_int(statement, 7, Int32(item.height))
        sqlite3_bind_int64(statement, 8, item.fileSize); sqlite3_bind_double(statement, 15, item.confidence)
        sqlite3_bind_int(statement, 18, item.isFavorite ? 1 : 0)
        bindDate(item.archivedAt, at: 19, in: statement); bindDate(item.deletedAt, at: 20, in: statement)
        sqlite3_bind_int(statement, 21, Int32(item.analysisVersion))
    }

    private func decode(_ row: OpaquePointer) -> ScreenshotItem {
        ScreenshotItem(
            id: UUID(uuidString: string(row, 0) ?? "") ?? UUID(), fileURL: URL(fileURLWithPath: string(row, 1) ?? ""),
            filename: string(row, 2) ?? "", createdAt: Date(timeIntervalSince1970: sqlite3_column_double(row, 3)),
            importedAt: Date(timeIntervalSince1970: sqlite3_column_double(row, 4)), width: Int(sqlite3_column_int(row, 5)),
            height: Int(sqlite3_column_int(row, 6)), fileSize: sqlite3_column_int64(row, 7), sourceApp: string(row, 8),
            sourceBundleID: string(row, 9), ocrText: string(row, 10), detectedURLs: decodeStrings(string(row, 11)).compactMap(URL.init(string:)),
            detectedQRPayloads: decodeStrings(string(row, 12)), type: .init(rawValue: string(row, 13) ?? "") ?? .unknown,
            confidence: sqlite3_column_double(row, 14),
            analysisStatus: .init(rawValue: string(row, 15) ?? "") ?? .pending,
            workflowStatus: .init(rawValue: string(row, 16) ?? "") ?? .inbox,
            isFavorite: sqlite3_column_int(row, 17) != 0, archivedAt: date(row, 18), deletedAt: date(row, 19),
            analysisVersion: Int(sqlite3_column_int(row, 20))
        )
    }

    private func bindText(_ value: String?, at index: Int32, in statement: OpaquePointer) {
        if let value { sqlite3_bind_text(statement, index, value, -1, sqliteTransient) } else { sqlite3_bind_null(statement, index) }
    }
    private func bindDate(_ value: Date?, at index: Int32, in statement: OpaquePointer) {
        if let value { sqlite3_bind_double(statement, index, value.timeIntervalSince1970) } else { sqlite3_bind_null(statement, index) }
    }
    private func string(_ row: OpaquePointer, _ index: Int32) -> String? {
        sqlite3_column_text(row, index).map { String(cString: $0) }
    }
    private func date(_ row: OpaquePointer, _ index: Int32) -> Date? {
        sqlite3_column_type(row, index) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(row, index))
    }
    private func encode(_ strings: [String]) -> String { String(data: (try? JSONEncoder().encode(strings)) ?? Data("[]".utf8), encoding: .utf8) ?? "[]" }
    private func decodeStrings(_ value: String?) -> [String] { (try? JSONDecoder().decode([String].self, from: Data((value ?? "[]").utf8))) ?? [] }

    private func migrate() throws {
        let statement = try database.prepare("PRAGMA user_version;")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw DatabaseError.statement("Unable to read schema version") }
        let version = Int(sqlite3_column_int(statement, 0))
        if version == 0 {
            let tableCheck = try database.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='screenshots';")
            defer { sqlite3_finalize(tableCheck) }
            if sqlite3_step(tableCheck) == SQLITE_ROW {
                try migrateV1ToV2()
            } else {
                try database.execute(Self.schemaV2 + "\nPRAGMA user_version=2;")
            }
        } else if version == 1 {
            try migrateV1ToV2()
        }
    }

    private func migrateV1ToV2() throws {
        try database.execute("""
        BEGIN IMMEDIATE;
        ALTER TABLE screenshots ADD COLUMN analysis_status TEXT NOT NULL DEFAULT 'pending';
        ALTER TABLE screenshots ADD COLUMN workflow_status TEXT NOT NULL DEFAULT 'inbox';
        UPDATE screenshots SET analysis_status = CASE status
          WHEN 'analyzing' THEN 'analyzing' WHEN 'ready' THEN 'ready'
          WHEN 'analysisFailed' THEN 'failed' WHEN 'archived' THEN 'ready'
          WHEN 'deleted' THEN 'ready' ELSE 'pending' END;
        UPDATE screenshots SET workflow_status = CASE status
          WHEN 'archived' THEN 'archived' WHEN 'deleted' THEN 'deleted' ELSE 'inbox' END;
        PRAGMA user_version=2;
        COMMIT;
        """)
    }

    private static let schemaV2 = """
    CREATE TABLE IF NOT EXISTS screenshots (
      id TEXT PRIMARY KEY, file_url TEXT NOT NULL UNIQUE, filename TEXT NOT NULL,
      created_at REAL NOT NULL, imported_at REAL NOT NULL, width INTEGER NOT NULL, height INTEGER NOT NULL,
      file_size INTEGER NOT NULL, source_app TEXT, source_bundle_id TEXT, ocr_text TEXT,
      detected_urls TEXT NOT NULL DEFAULT '[]', detected_qr_payloads TEXT NOT NULL DEFAULT '[]',
      type TEXT NOT NULL, confidence REAL NOT NULL, analysis_status TEXT NOT NULL,
      workflow_status TEXT NOT NULL, is_favorite INTEGER NOT NULL DEFAULT 0,
      archived_at REAL, deleted_at REAL, analysis_version INTEGER NOT NULL DEFAULT 0
    );
    CREATE INDEX IF NOT EXISTS screenshots_created_at ON screenshots(created_at DESC);
    """
}
