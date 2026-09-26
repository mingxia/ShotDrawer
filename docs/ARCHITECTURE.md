# Architecture Notes

## Guiding boundaries

ShotDrawer uses a vertical-slice approach while keeping its long-lived responsibilities separate:

- **Views** render state and forward user intent. They do not inspect screenshot content or decide which actions should exist.
- **App state** owns presentation-level selection and user preferences.
- **Services** will own filesystem watching, importing, Vision analysis, action generation, file operations, and thumbnails.
- **Database repositories** will own SQLite persistence and FTS5 queries.
- **Models** will remain independent from SwiftUI wherever possible.

The Phase 1 shell deliberately contains no placeholder network layer. Screenshot data will never need to leave the device.

## Screenshot detection (Phase 2)

The screenshot directory service will resolve the configured directory and retain a security-scoped bookmark. A filesystem-event-driven watcher will observe that directory rather than poll it. Candidate PNG, JPEG, and HEIC files will be checked for recency and stable size before being passed to the importer. Database identity will provide durable duplicate prevention.

Changing the configured directory will stop the existing watcher before a new watcher starts. Existing files will not be imported by default.

### Candidate classification (Phase 5A)

Stable image files pass through `ScreenshotCandidateClassifier` before any database write. The classifier combines independent evidence and uses a conservative threshold: native screenshot metadata is strongest, the localized default filename's date/time shape and creation recency are supporting signals, and PNG is only weak evidence. A `kMDItemWhereFroms` extended attribute is treated as strong contrary evidence so a recent browser download is ignored. Filename alone never reaches the threshold.

The metadata probes were selected from attributes observable on native macOS files: Spotlight's `kMDItemIsScreenCapture`, the corresponding `com.apple.metadata:kMDItemIsScreenCapture` extended attribute, and an ImageIO TIFF `Software` value that explicitly names `screencapture`/`screenshot`. There is no universal ImageIO screenshot flag, metadata availability varies by macOS version and filesystem, and copied/exported files can lose extended attributes; these signals are therefore combined rather than assumed. `kMDItemWhereFroms` reliably identifies many browser downloads but is not guaranteed for every browser. Candidate paths and metadata contents are not logged in release builds.

## Vision pipeline (Phase 4–5)

Analysis will run away from the main actor. OCR and barcode requests will be independent enhancements: either may fail without preventing the preliminary screenshot record from appearing in the inbox. URL extraction will combine `NSDataDetector`, URL validation, and a conservative fallback for domain-like text. Analysis results will be persisted before the UI and floating card are updated.

No OCR text or image content will be written to logs or telemetry.

`BarcodeService` runs a local Vision QR-only request alongside OCR. Either request may fail independently; analysis is marked failed only when both requests fail. URL-shaped QR payloads are added to the same action-compatible URL collection while the original payload is retained. `ScreenshotClassifier` owns the deterministic priority and scoring (`QR → Error → Website → Text → Unknown`), including conservative compound error heuristics so a lone “warning” or “error” does not override otherwise useful content.

## Database design (Phase 3 and Phase 8)

SQLite will store one canonical screenshot record. Status, creation time, type, and favorite state will be indexed. URL and QR payload arrays can initially be encoded as JSON. An FTS5 external-content index will cover filename, OCR text, detected URLs, source app, and type.

Archiving changes only record state and never moves the original file. Deletion will use the system Trash and mark the record deleted only after a safe file operation. Missing original files remain representable through cached thumbnails.

## File access model (Phase 2)

The app sandbox will grant user-selected read/write access to the screenshot directory. Access will be restored from a security-scoped bookmark at launch and balanced with `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()`. ShotDrawer will not request Screen Recording permission because macOS remains responsible for capture.

## Floating panel (Phase 7)

The floating card will be an `NSPanel` configured as non-activating so it cannot steal focus. It will appear near the lower-right corner of the active screen, host a SwiftUI card, and dismiss after a short delay. Pointer hover will suspend the timeout. Its three primary actions will come from `ActionEngine`; the panel will not reproduce classification rules.

The implemented panel uses both the `.nonactivatingPanel` style mask and a panel subclass that refuses key/main status. Its position is derived from the screen under the pointer and that screen's `visibleFrame`. A FIFO single-card queue prevents overlapping panels during rapid captures; queued copies of the same record are updated rather than duplicated. Dismissing a card never changes workflow state.

## Schema migrations

SQLite `PRAGMA user_version` is the migration authority. Schema v2 separates `analysis_status` from `workflow_status`; the v1 migration maps legacy analyzing/ready/failure states independently from archived/deleted workflow states without deleting the legacy data or moving screenshot files.
