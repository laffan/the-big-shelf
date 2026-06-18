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

    /// Progress while bulk-saving every cover for offline browsing.
    struct CoverCachingState: Equatable {
        var done: Int
        var total: Int
        var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
    }

    @Published private(set) var phase: Phase = .onboarding
    @Published private(set) var config: LibraryConfig?
    @Published private(set) var books: [Book] = []
    /// `books` pre-sorted by the current order; filtering preserves this order
    /// so we never re-sort on each keystroke.
    @Published private(set) var sortedBooks: [Book] = []
    @Published var searchText: String = ""
    @Published private(set) var coverCaching: CoverCachingState?

    @Published var sortOrder: LibrarySortOrder {
        didSet {
            UserDefaults.standard.set(sortOrder.rawValue, forKey: Self.sortKey)
            resort()
        }
    }

    private static let sortKey = "BigBookshelf.SortOrder"

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.sortKey)
        sortOrder = saved.flatMap(LibrarySortOrder.init(rawValue:)) ?? .dateAdded
    }

    /// Filtered + sorted view of the catalog by title or author.
    var displayedBooks: [Book] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return sortedBooks }
        let terms = query.split(separator: " ").map(String.init)
        return sortedBooks.filter { book in
            let haystack = book.searchHaystack
            return terms.allSatisfy { haystack.contains($0) }
        }
    }

    private func resort() {
        sortedBooks = sortOrder.sorted(books)
    }

    private var reader: CalibreMetadataReader?
    private var coverCacheTask: Task<Void, Never>?

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
            resort()
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
                resort()

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

    /// The on-disk URL for a downloaded format, if it has already been saved.
    func downloadedURL(for format: BookFormat, of book: Book) -> URL? {
        let fileName = format.exportFileName(title: book.title)
        return DownloadsStore.isDownloaded(bookId: book.id, fileName: fileName)
            ? DownloadsStore.fileURL(bookId: book.id, fileName: fileName)
            : nil
    }

    /// Downloads one format to persistent storage (kept until the user deletes
    /// it), reporting progress, and returns the saved file URL.
    func downloadFormat(_ format: BookFormat, of book: Book,
                        progress: @escaping (Double) -> Void) async throws -> URL {
        guard let config else { throw DropboxError.notAuthorized }
        let remotePath = PathUtil.join(config.rootPath, format.relativePath(bookPath: book.path))
        let fileName = format.exportFileName(title: book.title)
        let destination = DownloadsStore.fileURL(bookId: book.id, fileName: fileName)
        return try await DropboxService.shared.download(path: remotePath, to: destination) { fraction in
            Task { @MainActor in progress(fraction) }
        }
    }

    /// Removes a previously downloaded format from the device.
    func deleteDownload(_ format: BookFormat, of book: Book) {
        let fileName = format.exportFileName(title: book.title)
        DownloadsStore.delete(bookId: book.id, fileName: fileName)
    }

    // MARK: - Bulk cover caching (offline browsing)

    /// Pre-fetches and disk-caches every cover so the grid works without a fast
    /// connection. Bounded concurrency keeps memory and the network reasonable.
    func cacheAllCovers() {
        guard coverCacheTask == nil, let root = config?.rootPath else { return }
        let targets = books.filter(\.hasCover)
        guard !targets.isEmpty else { return }

        coverCaching = CoverCachingState(done: 0, total: targets.count)
        coverCacheTask = Task { [weak self] in
            await self?.runCoverCaching(targets: targets, root: root)
            self?.coverCaching = nil
            self?.coverCacheTask = nil
        }
    }

    func cancelCoverCaching() {
        coverCacheTask?.cancel()
    }

    private func runCoverCaching(targets: [Book], root: String) async {
        let maxConcurrent = 6
        await withTaskGroup(of: Void.self) { group in
            var iterator = targets.makeIterator()
            for _ in 0..<maxConcurrent {
                guard let book = iterator.next() else { break }
                group.addTask { _ = await CoverCache.shared.image(for: book, libraryRoot: root) }
            }
            while await group.next() != nil {
                if Task.isCancelled { break }
                coverCaching?.done += 1
                if let book = iterator.next() {
                    group.addTask { _ = await CoverCache.shared.image(for: book, libraryRoot: root) }
                }
            }
        }
    }

    // MARK: - Reset

    func signOut() {
        cancelCoverCaching()
        DropboxService.shared.unlink()
        LibraryConfig.clear()
        try? FileManager.default.removeItem(at: LocalStorage.metadataDatabaseURL)
        try? FileManager.default.removeItem(at: LocalStorage.downloadsDirectory)
        reader = nil
        books = []
        sortedBooks = []
        config = nil
        searchText = ""
        phase = .onboarding
    }
}
