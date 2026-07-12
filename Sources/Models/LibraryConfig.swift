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

    /// Dropbox path of the "inbox" folder the app uploads new books into for
    /// desktop Calibre's automatic adding to pick up. `nil` means use the
    /// default derived from `rootPath`. (Optional so configs saved by earlier
    /// versions still decode.)
    var inboxPath: String?

    /// Default inbox location: a "Calibre Inbox" folder *next to* the library
    /// root — never inside it, because Calibre refuses to auto-add from its
    /// own library folder and deletes files after importing them.
    static func defaultInboxPath(forRoot rootPath: String) -> String {
        let parent = (rootPath as NSString).deletingLastPathComponent
        return PathUtil.join(parent.isEmpty ? "/" : parent, "Calibre Inbox")
    }

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
