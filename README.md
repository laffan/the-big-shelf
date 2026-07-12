# The Big Bookshelf

A native **iOS / iPadOS** app that turns your Dropbox-hosted **Calibre** library
into a fast, searchable shelf of covers — and lets you send any book straight to
**Apple Books** (or any other app) via the system share sheet.

Built to stay smooth on **very large libraries** (7,000+ titles) without
crashing or stalling.

---

## Why native Swift (not Tauri)?

| Requirement | Why Swift/SwiftUI wins |
|---|---|
| Smooth scrolling over 7,000 covers | `LazyVGrid` + native image decode/cache; only on-screen cells exist |
| "Share to Apple Books" | It's literally a native `UIActivityViewController` ("Copy to Books") |
| Dropbox integration | First-party `SwiftyDropbox` SDK (OAuth PKCE, downloads, thumbnails) |
| Reading Calibre's catalog | Native SQLite via GRDB, reading Calibre's own `metadata.db` |

A Tauri webview would fight the OS on large-grid performance and on the
share-to-Books hand-off. For this specific app, native is the right call.

---

## The key idea: read `metadata.db`, don't crawl folders

A Calibre library contains a single SQLite file, **`metadata.db`**, at its root.
It holds *everything* — every title, author, series, tag, available format, and
whether a cover exists — for all 7,000 books.

So the app:

1. **Downloads one file** (`metadata.db`), instead of listing thousands of
   Dropbox folders (which would be thousands of slow API calls).
2. Reads it locally with SQLite and shows the full grid instantly from cache.
3. **Syncs incrementally:** on launch / pull-to-refresh it checks the Dropbox
   `rev` of `metadata.db`. If unchanged, it does nothing. If changed (you added
   books in Calibre), it re-downloads just that one small file and rebuilds the
   list — **new titles appear without re-downloading anything else.**
4. **Covers** are fetched lazily as small thumbnails *only when a cell scrolls
   into view*, then cached to disk forever. New books simply miss the cache and
   fetch once.
5. **Format files** (the actual EPUB/PDF) are downloaded only when you tap
   *Send* on a specific format.

This is what keeps it fast and crash-free at scale.

---

## Project layout

```
Sources/
  App/        BigBookshelfApp.swift   – entry point, Dropbox OAuth redirect
  Models/     Book, BookFormat, LibraryConfig
  Dropbox/    DropboxService          – async wrapper over SwiftyDropbox
  Library/    CalibreMetadataReader   – reads metadata.db (GRDB/SQLite)
              AppState                – sync orchestration + search
              CoverCache              – lazy 2-tier (memory + disk) thumbnails
              LocalStorage, PathUtil
  Views/      Onboarding, FolderPicker, LibraryGrid, BookCoverCell,
              BookDetail, ShareSheet, RootView
  Utilities/  UIApplication+TopViewController
Resources/    Info.plist, Assets.xcassets
Config/       Secrets.xcconfig.example
project.yml   XcodeGen project definition
```

---

## Building (requires a Mac with Xcode)

> iOS apps can only be compiled on macOS with Xcode — this repo is the source,
> not a prebuilt binary.

1. **Install tools**
   ```sh
   brew install xcodegen      # generates the .xcodeproj from project.yml
   ```

2. **Create a Dropbox app & add your key**
   - Go to <https://www.dropbox.com/developers/apps> → *Create app* →
     *Scoped access* → *Full Dropbox*.
   - On **Permissions**, enable: `account_info.read`, `files.metadata.read`,
     `files.content.read`, `files.content.write` (the write scope is used only
     to upload new books into the inbox folder — see *Adding books from your
     phone* below).
   - Copy the **App key** from **Settings**.
   - Then:
     ```sh
     cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
     # edit Config/Secrets.xcconfig and paste your key into DROPBOX_APP_KEY
     ```

3. **Generate and open the project**
   ```sh
   xcodegen generate
   open BigBookshelf.xcodeproj
   ```

4. In Xcode, set your **Development Team** (Signing & Capabilities) and run on a
   device or simulator.

### Dependencies (resolved automatically by SPM)
- [SwiftyDropbox](https://github.com/dropbox/SwiftyDropbox) — Dropbox API
- [GRDB.swift](https://github.com/groue/GRDB.swift) — SQLite access

---

## Using the app

1. **Connect Dropbox** — sign in (PKCE OAuth; no secret stored in the app).
2. **Choose your library** — browse to the Calibre folder that contains
   `metadata.db` and tap *Use This Folder*.
3. The grid loads. **Search** by title or author at the top.
4. Tap a cover → see info and **Available Formats** → tap **Send** on a format
   to download it and open the share sheet → choose **Copy to Books**.
5. Pull to refresh (or *Refresh Catalog* in the menu) to pick up new titles.

---

## Adding books from your phone

The **+** button on the shelf lets you pick book files (EPUB, PDF, MOBI, AZW3,
CBZ, …) with the system Files picker and upload them to a Dropbox **inbox
folder** — by default `Calibre Inbox`, created *next to* your library folder.
Desktop Calibre then imports them using its built-in **Automatic adding**
feature, so the library database is only ever written by Calibre itself (safe
by design — no risk of corrupting `metadata.db`).

**One-time setup on your laptop:**

1. In Calibre: **Preferences → Adding books → Automatic adding**.
2. Set the folder to the *local synced copy* of the inbox, e.g.
   `~/Dropbox/Books/Calibre Inbox`.
3. That's it. While Calibre is running (it also checks a couple of seconds
   after launch), any file that appears in that folder is imported into the
   library and **deleted from the folder** — that's how the app's
   *Waiting for Calibre* list empties itself.

Notes:

- The inbox **must not be inside the Calibre library folder** — Calibre
  refuses to watch its own library. The app's default (a sibling folder) is
  safe; you can change it from the **+** screen.
- The flow is: upload from phone → Dropbox syncs → Calibre imports on the
  laptop → Dropbox syncs the updated `metadata.db` back → pull-to-refresh
  shows the new book on your shelf. Until then, the file shows under
  *Waiting for Calibre* on the **+** screen.
- Single uploads are limited to 150 MB per file (Dropbox API limit); larger
  files should be added with desktop Calibre directly.
- **Existing installs:** the upload permission (`files.content.write`) was
  added later — enable it in the Dropbox App Console (Permissions tab), and
  the app will prompt you to re-connect Dropbox the first time you upload.

---

## Notes & possible next steps

- The folder picker verifies your choice on first sync; if `metadata.db` isn't
  found there, it tells you to pick the Calibre root.
- Calibre comment/description fields are HTML; they're shown as cleaned text.
- Possible enhancements: persistent download history, offline "my downloads"
  shelf, sort options (recent/author/series), and column-density settings.
- Because this can't be compiled in the Linux dev container it was authored in,
  a first `xcodegen generate` + build on a Mac may surface minor SDK signature
  tweaks if SwiftyDropbox's API drifts across versions (the SDK is pinned to
  10.x in `project.yml`).
