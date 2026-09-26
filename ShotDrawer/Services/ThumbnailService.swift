import AppKit
import Foundation

struct ThumbnailService {
    let cacheDirectory: URL

    func create(for item: ScreenshotItem) throws {
        let image = NSImage(contentsOf: item.fileURL)
        guard let image else { return }
        let target = NSSize(width: 480, height: 300)
        let thumbnail = NSImage(size: target)
        thumbnail.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: target), from: .zero, operation: .copy, fraction: 1)
        thumbnail.unlockFocus()
        guard let tiff = thumbnail.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return }
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try data.write(to: cacheDirectory.appendingPathComponent("\(item.id.uuidString).jpg"), options: .atomic)
    }

    func url(for id: UUID) -> URL { cacheDirectory.appendingPathComponent("\(id.uuidString).jpg") }
}
