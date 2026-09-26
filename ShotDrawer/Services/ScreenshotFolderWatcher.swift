import Darwin
import Foundation

final class ScreenshotFolderWatcher {
    typealias Handler = @Sendable (URL) -> Void

    private let queue = DispatchQueue(label: "com.shotdrawer.folder-watcher", qos: .utility)
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: Int32 = -1
    private var knownFiles = Set<String>()
    private var pendingFiles = Set<String>()
    private var folderURL: URL?
    private let handler: Handler

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    deinit { stop() }

    func start(watching url: URL) {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopOnQueue()
            self.folderURL = url
            self.knownFiles = self.currentImagePaths(in: url)
            self.descriptor = open(url.path, O_EVTONLY)
            guard self.descriptor >= 0 else {
                AppLogger.watcher.error("Unable to watch \(url.path, privacy: .public)")
                return
            }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: self.descriptor,
                eventMask: [.write, .extend, .attrib, .rename],
                queue: self.queue
            )
            source.setEventHandler { [weak self] in self?.scanForNewFiles() }
            source.setCancelHandler { [descriptor = self.descriptor] in close(descriptor) }
            self.source = source
            source.resume()
            AppLogger.watcher.info("Watching screenshot folder: \(url.path, privacy: .public)")
        }
    }

    func stop() {
        queue.sync { stopOnQueue() }
    }

    static func supports(_ url: URL) -> Bool {
        ["png", "jpg", "jpeg", "heic"].contains(url.pathExtension.lowercased())
    }

    private func stopOnQueue() {
        source?.cancel()
        source = nil
        descriptor = -1
        folderURL = nil
        knownFiles.removeAll()
        pendingFiles.removeAll()
    }

    private func currentImagePaths(in folder: URL) -> Set<String> {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return Set(urls.filter(Self.supports).map(\.standardizedFileURL.path))
    }

    private func scanForNewFiles() {
        guard let folderURL else { return }
        let current = currentImagePaths(in: folderURL)
        let additions = current.subtracting(knownFiles)
        knownFiles.formUnion(current)
        for path in additions where pendingFiles.insert(path).inserted {
            waitUntilStable(URL(fileURLWithPath: path), previousSize: nil, attemptsRemaining: 12)
        }
    }

    private func waitUntilStable(_ url: URL, previousSize: Int64?, attemptsRemaining: Int) {
        queue.asyncAfter(deadline: .now() + .milliseconds(250)) { [weak self] in
            guard let self else { return }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            let size = values?.fileSize.map(Int64.init)
            if values?.isRegularFile == true, let size, size > 0, size == previousSize {
                self.pendingFiles.remove(url.standardizedFileURL.path)
                AppLogger.watcher.info("New screenshot detected: \(url.path, privacy: .public)")
                self.handler(url)
            } else if attemptsRemaining > 0 {
                self.waitUntilStable(url, previousSize: size, attemptsRemaining: attemptsRemaining - 1)
            } else {
                self.pendingFiles.remove(url.standardizedFileURL.path)
                AppLogger.watcher.warning("Screenshot did not become stable: \(url.path, privacy: .public)")
            }
        }
    }
}
