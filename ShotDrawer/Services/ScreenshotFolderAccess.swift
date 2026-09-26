import AppKit
import Foundation

@MainActor
final class ScreenshotFolderAccess: ObservableObject {
    @Published private(set) var folderURL: URL?

    private let defaults: UserDefaults
    private var accessingURL: URL?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        restoreBookmark()
    }

    deinit {
        accessingURL?.stopAccessingSecurityScopedResource()
    }

    var displayPath: String {
        folderURL?.path ?? "Choose a folder"
    }

    @discardableResult
    func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose Screenshot Folder"
        panel.message = "ShotDrawer watches this folder for new screenshots."
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = folderURL ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        save(url)
        return url
    }

    private func restoreBookmark() {
        guard let data = defaults.data(forKey: PreferenceKey.screenshotFolderBookmark) else { return }
        do {
            var stale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            activate(url)
            if stale { save(url) }
        } catch {
            AppLogger.file.error("Unable to restore screenshot folder bookmark: \(error.localizedDescription, privacy: .public)")
            defaults.removeObject(forKey: PreferenceKey.screenshotFolderBookmark)
        }
    }

    private func save(_ url: URL) {
        do {
            let data = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(data, forKey: PreferenceKey.screenshotFolderBookmark)
            activate(url)
        } catch {
            AppLogger.file.error("Unable to save screenshot folder bookmark: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func activate(_ url: URL) {
        accessingURL?.stopAccessingSecurityScopedResource()
        guard url.startAccessingSecurityScopedResource() else {
            AppLogger.file.error("Security-scoped access was denied for \(url.path, privacy: .public)")
            folderURL = nil
            accessingURL = nil
            return
        }
        accessingURL = url
        folderURL = url
    }
}
