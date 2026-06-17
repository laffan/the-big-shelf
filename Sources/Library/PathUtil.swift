import Foundation

enum PathUtil {
    /// Joins a Dropbox library root with a relative path inside the library.
    static func join(_ root: String, _ relative: String) -> String {
        let trimmedRoot = root.hasSuffix("/") ? String(root.dropLast()) : root
        let trimmedRel = relative.hasPrefix("/") ? String(relative.dropFirst()) : relative
        return trimmedRoot + "/" + trimmedRel
    }
}
