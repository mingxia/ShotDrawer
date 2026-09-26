# ShotDrawer

> A smarter home for your screenshots.

中文名称：截图抽屉

ShotDrawer is a local-first native macOS utility built around the intent behind screenshots. It keeps the familiar macOS screenshot workflow, then helps you understand, act on, find, organize, and remove screenshots without leaving them scattered across the Desktop.

## Product model

**Capture → Understand → Act → Manage**

- **Capture:** Keep using the macOS screenshot shortcuts you already know.
- **Understand:** ShotDrawer recognizes text, links, QR codes, errors, and other useful content locally.
- **Act:** Take the next useful action directly from the screenshot.
- **Manage:** Browse screenshots visually, find them quickly, keep what matters, and remove what no longer does.

## Current milestone: Phase 7

The application now implements the local capture-to-action workflow:

- sandbox-safe screenshot-folder selection and an event-driven folder watcher;
- automatic SQLite import, persistent records, and thumbnail caching;
- a database-backed Inbox that refreshes as screenshots arrive;
- on-device Apple Vision OCR plus local URL extraction;
- local QR detection and deterministic screenshot classification;
- contextual actions, Archive, Favorites, safe Trash, and Inbox Zero;
- a non-activating queued floating action card and recent menu-bar items.

The application makes no network requests and never modifies or relocates source screenshots.

## Requirements

- macOS 13.0 or later
- Xcode 15 or later

macOS 13 is the minimum deployment target because the shell uses `MenuBarExtra`. No newer OS-only API is currently required.

## Build and run

1. Open `ShotDrawer.xcodeproj` in Xcode.
2. Select the **ShotDrawer** scheme and **My Mac** destination.
3. Press **Run** (`⌘R`).

Or build from Terminal on macOS:

```sh
xcodebuild -project ShotDrawer.xcodeproj \
  -scheme ShotDrawer \
  -destination 'platform=macOS' build
```

Run the test suite with:

```sh
xcodebuild -project ShotDrawer.xcodeproj \
  -scheme ShotDrawer \
  -destination 'platform=macOS' test
```

## Architecture

The project starts with boundaries that later vertical slices can extend without moving filesystem, analysis, database, or action logic into views:

```text
ShotDrawer/
├── App/          # lifecycle and shared observable state
├── Models/       # domain and navigation types
├── Services/     # filesystem, analysis, and action services (Phase 2+)
├── Database/     # SQLite repositories and migrations (Phase 3+)
├── Views/        # main window, menu bar, settings, and components
└── Utilities/    # constants and unified logging
```

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for implementation notes and planned module boundaries.

## Permissions

The app uses a user-selected screenshot directory and persists access with a security-scoped bookmark. It does not request Screen Recording or Accessibility access.

## Local data

Folder bookmarks are stored in `UserDefaults`; the SQLite database and thumbnail cache are stored under:

```text
~/Library/Application Support/ShotDrawer/
```

Screenshots and extracted content remain on the Mac. ShotDrawer is local-first and has no account, backend, analytics SDK, telemetry, or screenshot upload.

## Known limitations

- Screenshot source-app attribution is not available from ordinary image files and remains empty.
- OCR quality depends on Apple Vision and the source image; failed OCR remains imported and is marked accordingly.
- Candidate metadata differs across macOS versions and filesystems, so conservative detection can occasionally miss a screenshot.
- Search, AI understanding, cloud sync, and managed libraries are intentionally outside this milestone.

## Tests

The unit-test target covers candidate and content classification, action generation, schema migration, workflow persistence, Trash failure ordering, duplicate prevention, URL extraction, and extension filtering.
