import Foundation

/// Persisted, one-time configuration for the connected Calibre library.
///
/// Stored in `UserDefaults` once onboarding completes so the app skips straight
/// to the grid on subsequent launches.
struct LibraryConfig: Codable, Equatable {
    /// Dropbox path of the Calibre library root (the folder containing
    /// `metadata.db`), e.g. "/Books/Calibre Library".
    var rootPath: String

    /// Dropbox `rev` of `metadata.db` the last time we synced. Used to skip the
    /// download entirely when nothing has changed.
    var metadataRev: String?

    /// When we last successfully synced the catalog.
    var lastSynced: Date?

    private static let key = "BigBookshelf.LibraryConfig"

    static func load() -> LibraryConfig? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(LibraryConfig.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
