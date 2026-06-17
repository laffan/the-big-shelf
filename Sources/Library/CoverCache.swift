import Foundation
import UIKit

/// Lazily fetches and caches book cover thumbnails.
///
/// Two tiers: an in-memory `NSCache` for instant scrolling, and a disk cache so
/// covers survive relaunches and we never re-download them. New books simply
/// miss the cache and fetch once; nothing else is re-downloaded.
actor CoverCache {
    static let shared = CoverCache()

    private let memory = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    /// De-duplicates concurrent requests for the same cover while one is in flight.
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    init() {
        memory.countLimit = 400 // plenty for what's on screen; covers are small
    }

    /// Returns a cover image for `book`, fetching from Dropbox if needed.
    /// `libraryRoot` is the Dropbox path of the Calibre library root.
    func image(for book: Book, libraryRoot: String) async -> UIImage? {
        guard book.hasCover else { return nil }
        let key = cacheKey(for: book)

        if let cached = memory.object(forKey: key as NSString) {
            return cached
        }

        if let existing = inFlight[key] {
            return await existing.value
        }

        let task = Task<UIImage?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.load(book: book, libraryRoot: libraryRoot, key: key)
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        return image
    }

    private func load(book: Book, libraryRoot: String, key: String) async -> UIImage? {
        let fileURL = LocalStorage.coverCacheDirectory.appendingPathComponent(key + ".jpg")

        // Disk hit.
        if let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) {
            memory.setObject(image, forKey: key as NSString)
            return image
        }

        // Network fetch (thumbnail keeps it tiny and fast even for 7,000 books).
        let dropboxPath = joinPath(libraryRoot, book.coverRelativePath)
        do {
            let data = try await DropboxService.shared.thumbnail(path: dropboxPath)
            try? data.write(to: fileURL)
            guard let image = UIImage(data: data) else { return nil }
            memory.setObject(image, forKey: key as NSString)
            return image
        } catch {
            return nil
        }
    }

    /// Stable, filesystem-safe key derived from the book's library path.
    private func cacheKey(for book: Book) -> String {
        let raw = book.path.isEmpty ? "book-\(book.id)" : book.path
        return raw.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    private func joinPath(_ root: String, _ relative: String) -> String {
        let trimmedRoot = root.hasSuffix("/") ? String(root.dropLast()) : root
        return trimmedRoot + "/" + relative
    }

    /// Clears in-memory covers (e.g. on a memory warning). Disk cache is kept.
    func purgeMemory() {
        memory.removeAllObjects()
    }
}
