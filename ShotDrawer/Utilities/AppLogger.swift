import OSLog

enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.shotdrawer.app"

    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let watcher = Logger(subsystem: subsystem, category: "watcher")
    static let `import` = Logger(subsystem: subsystem, category: "import")
    static let analysis = Logger(subsystem: subsystem, category: "analysis")
    static let database = Logger(subsystem: subsystem, category: "database")
    static let action = Logger(subsystem: subsystem, category: "action")
    static let file = Logger(subsystem: subsystem, category: "file")
}
