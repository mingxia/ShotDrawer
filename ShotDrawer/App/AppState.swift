import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var selection: SidebarDestination? = .inbox
    @Published private(set) var inboxCount = 0
    @Published private(set) var screenshots: [ScreenshotItem] = []
    @Published var selectedScreenshotID: UUID?
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    let folderAccess: ScreenshotFolderAccess
    let thumbnailService: ThumbnailService
    let actionEngine = ActionEngine()
    let presentationService = ScreenshotPresentationService()
    private let repository: ScreenshotRepository
    private let importer: ScreenshotImporter
    private let analyzer: ScreenshotAnalyzer
    private let actionExecutor: ActionExecutor
    private var watcher: ScreenshotFolderWatcher!
    private var floatingPanel: FloatingPanelController!
    private var didOfferFolderSelection = false

    @AppStorage(PreferenceKey.showFloatingCard) var showFloatingCard = true
    @AppStorage(PreferenceKey.showInboxCount) var showInboxCount = true
    @AppStorage(PreferenceKey.extractText) var extractText = true
    @AppStorage(PreferenceKey.detectLinks) var detectLinks = true
    @AppStorage(PreferenceKey.detectQRCodes) var detectQRCodes = true

    init() {
        let folderAccess = ScreenshotFolderAccess()
        self.folderAccess = folderAccess
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShotDrawer", isDirectory: true)
        try? FileManager.default.createDirectory(at: applicationSupport, withIntermediateDirectories: true)
        do {
            repository = try ScreenshotRepository(databaseURL: applicationSupport.appendingPathComponent("ShotDrawer.sqlite"))
        } catch {
            fatalError("Unable to open local screenshot database: \(error)")
        }
        thumbnailService = ThumbnailService(cacheDirectory: applicationSupport.appendingPathComponent("Thumbnails", isDirectory: true))
        importer = ScreenshotImporter(repository: repository, thumbnails: thumbnailService)
        analyzer = ScreenshotAnalyzer(repository: repository)
        actionExecutor = ActionExecutor(repository: repository)
        watcher = ScreenshotFolderWatcher { [weak self] url in
            Task { await self?.importAndRefresh(url) }
        }
        floatingPanel = FloatingPanelController(appState: self)
        if let url = folderAccess.folderURL {
            watcher.start(watching: url)
        }
        Task { await refresh() }
    }

    func chooseScreenshotFolder() {
        if let url = folderAccess.chooseFolder() {
            watcher.start(watching: url)
        }
        objectWillChange.send()
    }

    func offerFolderSelectionIfNeeded() {
        guard folderAccess.folderURL == nil, !didOfferFolderSelection else { return }
        didOfferFolderSelection = true
        chooseScreenshotFolder()
    }

    var selectedScreenshot: ScreenshotItem? {
        screenshots.first { $0.id == selectedScreenshotID }
    }

    func refresh() async {
        do {
            screenshots = try await repository.fetchAll()
            inboxCount = screenshots.filter { $0.workflowStatus == .inbox }.count
        } catch {
            AppLogger.database.error("Unable to load screenshots: \(error.localizedDescription, privacy: .public)")
        }
    }

    func perform(_ action: SuggestedAction, for item: ScreenshotItem) async {
        do {
            _ = try await actionExecutor.execute(action, for: item)
            await refresh()
            if !screenshots.contains(where: { $0.id == selectedScreenshotID }) { selectedScreenshotID = nil }
        } catch {
            AppLogger.action.error("Action failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func archiveAllInbox() async {
        do { try await repository.archiveInbox(at: Date()); await refresh() }
        catch { AppLogger.database.error("Unable to archive Inbox: \(error.localizedDescription, privacy: .public)") }
    }

    private func importAndRefresh(_ url: URL) async {
        do {
            guard let item = try await importer.importScreenshot(at: url) else { return }
            AppLogger.import.info("Imported screenshot: \(item.fileURL.path, privacy: .public)")
            await refresh()
            Task { @MainActor in
                let fallback = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(4))
                    guard !Task.isCancelled else { return }
                    self?.floatingPanel.show(item)
                }
                let options = AnalysisOptions(
                    extractText: extractText,
                    detectLinks: extractText && detectLinks,
                    detectQRCodes: detectQRCodes
                )
                await analyzer.analyze(item, options: options)
                fallback.cancel()
                await refresh()
                if let analyzed = screenshots.first(where: { $0.id == item.id }) {
                    floatingPanel.show(analyzed)
                }
            }
        } catch {
            AppLogger.import.error("Screenshot import failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    var menuBarLabel: String {
        showInboxCount && inboxCount > 0 ? "ShotDrawer · \(inboxCount)" : "ShotDrawer"
    }

    var attentionSummary: String {
        switch inboxCount {
        case 0: "All screenshots handled."
        case 1: "1 screenshot needs attention"
        default: "\(inboxCount) screenshots need attention"
        }
    }

    func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { !($0 is NSPanel) })?.makeKeyAndOrderFront(nil)
    }

    func openScreenshot(_ item: ScreenshotItem) {
        selection = .allScreenshots
        selectedScreenshotID = item.id
        openMainWindow()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            AppLogger.ui.error("Unable to update launch at login: \(error.localizedDescription, privacy: .public)")
        }
    }

    func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
