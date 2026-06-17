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

    /// A temporary location for a freshly downloaded format file, ready to share.
    static func temporaryExportURL(fileName: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    }
}
