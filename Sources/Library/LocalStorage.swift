import Foundation

/// Centralises the on-device locations the app writes to.
enum LocalStorage {
    /// Application Support holds data we want to persist (the catalog DB).
    static var supportDirectory: URL {
        let url = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BigBookshelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Caches holds regenerable data (cover thumbnails) the OS may evict.
    static var coverCacheDirectory: URL {
        let url = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Where the downloaded Calibre `metadata.db` lives.
    static var metadataDatabaseURL: URL {
        supportDirectory.appendingPathComponent("metadata.db")
    }

    /// Persistent home for downloaded book files. They stay until the user
    /// deletes them, so books are available offline once downloaded.
    static var downloadsDirectory: URL {
        let url = supportDirectory.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// Tracks downloaded format files on disk. The filesystem is the source of
/// truth — a file's presence means it's downloaded.
enum DownloadsStore {
    private static func bookDirectory(_ bookId: Int64) -> URL {
        let url = LocalStorage.downloadsDirectory.appendingPathComponent("\(bookId)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func fileURL(bookId: Int64, fileName: String) -> URL {
        bookDirectory(bookId).appendingPathComponent(fileName)
    }

    static func isDownloaded(bookId: Int64, fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(bookId: bookId, fileName: fileName).path)
    }

    static func delete(bookId: Int64, fileName: String) {
        try? FileManager.default.removeItem(at: fileURL(bookId: bookId, fileName: fileName))
    }
}
