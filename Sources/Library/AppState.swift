import Foundation
import SwiftUI

/// Top-level observable state driving the whole app.
@MainActor
final class AppState: ObservableObject {

    enum Phase: Equatable {
        case onboarding          // not connected / no library chosen yet
        case syncing(String)     // a status message to show
        case ready
        case failed(String)
    }

    @Published private(set) var phase: Phase = .onboarding
    @Published private(set) var config: LibraryConfig?
    @Published private(set) var books: [Book] = []
    @Published var searchText: String = ""

    /// Filtered, case-insensitive view of the catalog by title or author.
    var filteredBooks: [Book] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return books }
        let terms = query.split(separator: " ").map(String.init)
        return books.filter { book in
            let haystack = book.searchHaystack
            return terms.allSatisfy { haystack.contains($0) }
        }
    }

    private var reader: CalibreMetadataReader?

    // MARK: - Launch

    /// Decides where to start: onboarding, or straight to a cached catalog.
    func bootstrap() {
        config = LibraryConfig.load()

        if let config, DropboxService.shared.isAuthorized {
            // We have a library and a session — show whatever we cached, then
            // sync in the background to pick up new titles.
            if loadCachedCatalog() {
                phase = .ready
                Task { await sync() }
            } else {
                Task { await sync() }
            }
        } else {
            phase = .onboarding
        }
    }

    /// Loads books from the metadata.db we already have on disk, if any.
    @discardableResult
    private func loadCachedCatalog() -> Bool {
        guard FileManager.default.fileExists(atPath: LocalStorage.metadataDatabaseURL.path) else {
            return false
        }
        do {
            let reader = try CalibreMetadataReader(path: LocalStorage.metadataDatabaseURL.path)
            self.reader = reader
            self.books = try reader.loadAllBooks()
            return !books.isEmpty
        } catch {
            return false
        }
    }

    // MARK: - Onboarding

    /// Called after Dropbox OAuth succeeds and the user picks the library root.
    func completeOnboarding(rootPath: String) {
        let config = LibraryConfig(rootPath: rootPath, metadataRev: nil, lastSynced: nil)
        config.save()
        self.config = config
        Task { await sync(force: true) }
    }

    // MARK: - Sync

    /// Downloads `metadata.db` only when its Dropbox `rev` has changed, then
    /// rebuilds the in-memory catalog. Covers and format files are never part of
    /// this step — they are fetched lazily and cached separately.
    func sync(force: Bool = false) async {
        guard let config else { phase = .onboarding; return }
        guard DropboxService.shared.isAuthorized else { phase = .onboarding; return }

        let metadataPath = PathUtil.join(config.rootPath, "metadata.db")

        if books.isEmpty {
            phase = .syncing("Loading your library…")
        }

        do {
            let remoteRev = try await DropboxService.shared.fileRev(path: metadataPath)
            guard let remoteRev else {
                phase = .failed("Couldn't find metadata.db in the selected folder. Make sure you picked your Calibre library root.")
                return
            }

            let needsDownload = force
                || config.metadataRev != remoteRev
                || !FileManager.default.fileExists(atPath: LocalStorage.metadataDatabaseURL.path)

            if needsDownload {
                if books.isEmpty {
                    phase = .syncing("Downloading catalog…")
                }
                try await DropboxService.shared.download(
                    path: metadataPath,
                    to: LocalStorage.metadataDatabaseURL
                )

                if books.isEmpty {
                    phase = .syncing("Reading your books…")
                }
                let reader = try CalibreMetadataReader(path: LocalStorage.metadataDatabaseURL.path)
                self.reader = reader
                self.books = try reader.loadAllBooks()

                var updated = config
                updated.metadataRev = remoteRev
                updated.lastSynced = Date()
                updated.save()
                self.config = updated
            } else if reader == nil {
                // Rev unchanged but we haven't opened the DB yet this launch.
                loadCachedCatalog()
            }

            phase = .ready
        } catch {
            if !books.isEmpty {
                // We can still show the cached catalog; surface a soft failure.
                phase = .ready
            } else {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Detail & downloads

    func loadDetail(for book: Book) -> BookDetail? {
        guard let reader else { return nil }
        return try? reader.loadDetail(bookId: book.id)
    }

    /// Downloads one format to a temporary file and returns its URL, ready to
    /// hand to a share sheet (e.g. "Copy to Books").
    func downloadFormat(_ format: BookFormat, of book: Book) async throws -> URL {
        guard let config else { throw DropboxError.notAuthorized }
        let remotePath = PathUtil.join(config.rootPath, format.relativePath(bookPath: book.path))
        let destination = LocalStorage.temporaryExportURL(
            fileName: format.exportFileName(title: book.title)
        )
        return try await DropboxService.shared.download(path: remotePath, to: destination)
    }

    // MARK: - Reset

    func signOut() {
        DropboxService.shared.unlink()
        LibraryConfig.clear()
        try? FileManager.default.removeItem(at: LocalStorage.metadataDatabaseURL)
        reader = nil
        books = []
        config = nil
        searchText = ""
        phase = .onboarding
    }
}
