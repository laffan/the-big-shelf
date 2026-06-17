import Foundation
import SwiftyDropbox

/// A minimal entry returned when browsing Dropbox folders during onboarding.
struct DropboxFolderEntry: Identifiable, Hashable {
    var id: String { pathLower }
    let name: String
    let pathLower: String
    let pathDisplay: String
}

enum DropboxError: LocalizedError {
    case notAuthorized
    case missingAppKey
    case requestFailed(String)
    case fileNotFound(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Not signed in to Dropbox."
        case .missingAppKey:
            return "Dropbox app key is not configured. See Config/Secrets.xcconfig."
        case .requestFailed(let message):
            return message
        case .fileNotFound(let path):
            return "File not found in Dropbox: \(path)"
        }
    }
}

/// Async/await wrapper over the (callback-based) SwiftyDropbox SDK.
///
/// Everything the app needs from Dropbox funnels through here: OAuth state,
/// browsing folders, reading file metadata (`rev`), downloading files, and
/// fetching cover thumbnails.
final class DropboxService {
    static let shared = DropboxService()
    private init() {}

    /// Reads the Dropbox app key injected into Info.plist from Secrets.xcconfig.
    static var appKey: String? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "DropboxAppKey") as? String,
              !key.isEmpty,
              key != "paste_your_app_key_here" else {
            return nil
        }
        return key
    }

    /// Call once at launch.
    static func configure() {
        guard let appKey else {
            print("⚠️ Big Bookshelf: DropboxAppKey missing. Set it in Config/Secrets.xcconfig.")
            return
        }
        DropboxClientsManager.setupWithAppKeyMobile(appKey)
    }

    var isAuthorized: Bool { DropboxClientsManager.authorizedClient != nil }

    private var client: DropboxClient {
        get throws {
            guard let client = DropboxClientsManager.authorizedClient else {
                throw DropboxError.notAuthorized
            }
            return client
        }
    }

    func unlink() {
        DropboxClientsManager.unlinkClients()
    }

    // MARK: - Browsing folders (onboarding)

    /// Lists immediate sub-folders of `path` ("" for the Dropbox root),
    /// following pagination so large folders are fully enumerated.
    func listFolders(path: String) async throws -> [DropboxFolderEntry] {
        let client = try client
        var entries: [Files.Metadata] = []
        var result = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Files.ListFolderResult, Error>) in
            client.files.listFolder(path: path).response { response, error in
                Self.resume(cont, response, error)
            }
        }
        entries.append(contentsOf: result.entries)

        while result.hasMore {
            let cursor = result.cursor
            result = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Files.ListFolderResult, Error>) in
                client.files.listFolderContinue(cursor: cursor).response { response, error in
                    Self.resume(cont, response, error)
                }
            }
            entries.append(contentsOf: result.entries)
        }

        return entries
            .compactMap { $0 as? Files.FolderMetadata }
            .map { DropboxFolderEntry(name: $0.name,
                                      pathLower: $0.pathLower ?? "",
                                      pathDisplay: $0.pathDisplay ?? $0.name) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - File metadata

    /// Returns the current `rev` of a file, or nil if it does not exist.
    func fileRev(path: String) async throws -> String? {
        let client = try client
        do {
            let metadata = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Files.Metadata, Error>) in
                client.files.getMetadata(path: path).response { response, error in
                    Self.resume(cont, response, error)
                }
            }
            return (metadata as? Files.FileMetadata)?.rev
        } catch DropboxError.fileNotFound {
            return nil
        }
    }

    // MARK: - Downloads

    /// Downloads a file to `destination`, overwriting any existing file there.
    @discardableResult
    func download(path: String, to destination: URL) async throws -> URL {
        let client = try client
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            client.files.download(path: path, overwrite: true) { _, _ in destination }
                .response { response, error in
                    if let response {
                        cont.resume(returning: response.1)
                    } else {
                        cont.resume(throwing: Self.map(error))
                    }
                }
        }
    }

    /// Fetches a cover thumbnail as JPEG data.
    func thumbnail(path: String, size: Files.ThumbnailSize = .w256h256) async throws -> Data {
        let client = try client
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            client.files.getThumbnail(path: path, format: .jpeg, size: size).response { response, error in
                if let response {
                    cont.resume(returning: response.1)
                } else {
                    cont.resume(throwing: Self.map(error))
                }
            }
        }
    }

    // MARK: - Helpers

    private static func resume<T, E>(_ cont: CheckedContinuation<T, Error>, _ value: T?, _ error: CallError<E>?) {
        if let value {
            cont.resume(returning: value)
        } else {
            cont.resume(throwing: map(error))
        }
    }

    private static func map<E>(_ error: CallError<E>?) -> Error {
        guard let error else { return DropboxError.requestFailed("Unknown Dropbox error") }
        // Surface "path not found" so callers can treat a missing file as a
        // soft, recoverable condition.
        let description = error.description
        if description.localizedCaseInsensitiveContains("not_found") {
            return DropboxError.fileNotFound(description)
        }
        return DropboxError.requestFailed(description)
    }
}
