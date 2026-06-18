import Foundation

/// A lightweight book record, read from the Calibre `metadata.db`.
///
/// We keep these intentionally small so that the entire library (7,000+ titles)
/// can live comfortably in memory while the grid renders only what is visible.
/// Heavier data (cover images, format files) is fetched lazily and cached.
struct Book: Identifiable, Hashable {
    let id: Int64
    let title: String
    /// Calibre's `sort` column — used for stable alphabetical ordering.
    let titleSort: String
    let authors: [String]
    let authorSort: String
    /// Path of the book's folder relative to the library root,
    /// e.g. "Isaac Asimov/Foundation (42)".
    let path: String
    let hasCover: Bool
    let lastModified: Date?
    /// Calibre's `timestamp` — when the book was added to the library. Used for
    /// the default "recently added" ordering.
    let dateAdded: Date?
    /// Publication year, parsed from Calibre's `pubdate`.
    let publicationYear: Int?

    /// Lowercased title+authors, computed once at load so that filtering the
    /// whole catalog on each keystroke stays cheap even with thousands of books.
    let searchHaystack: String

    init(id: Int64, title: String, titleSort: String, authors: [String],
         authorSort: String, path: String, hasCover: Bool, lastModified: Date?,
         dateAdded: Date?, publicationYear: Int?) {
        self.id = id
        self.title = title
        self.titleSort = titleSort
        self.authors = authors
        self.authorSort = authorSort
        self.path = path
        self.hasCover = hasCover
        self.lastModified = lastModified
        self.dateAdded = dateAdded
        self.publicationYear = publicationYear
        self.searchHaystack = (title + " " + authors.joined(separator: " ")).lowercased()
    }

    /// Dropbox path (relative to library root) of the cover image.
    var coverRelativePath: String { path + "/cover.jpg" }

    var displayAuthors: String {
        authors.isEmpty ? "Unknown Author" : authors.joined(separator: ", ")
    }
}

/// One downloadable file format for a book (EPUB, MOBI, PDF, …).
struct BookFormat: Identifiable, Hashable {
    var id: String { format }
    /// Uppercase format name, e.g. "EPUB".
    let format: String
    /// Calibre's `data.name` — the filename without extension.
    let fileName: String
    let sizeBytes: Int64?

    /// Path of the format file relative to the library root.
    func relativePath(bookPath: String) -> String {
        bookPath + "/" + fileName + "." + format.lowercased()
    }

    /// Suggested filename when the user shares/exports the file.
    func exportFileName(title: String) -> String {
        let safeTitle = title.replacingOccurrences(of: "/", with: "-")
        return safeTitle + "." + format.lowercased()
    }
}

/// Full detail for a single book, loaded on demand when the detail view opens.
struct BookDetail {
    let comments: String?
    let formats: [BookFormat]
    let series: String?
    let seriesIndex: Double?
    let tags: [String]
    let publishedDate: Date?
}

/// How the cover grid is ordered.
enum LibrarySortOrder: String, CaseIterable, Identifiable {
    case dateAdded      // most recently added first (default)
    case authorLastName // Calibre author_sort is "Last, First"
    case title
    case year           // newest publication first

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dateAdded:      return "Date Added"
        case .authorLastName: return "Author"
        case .title:          return "Title"
        case .year:           return "Year"
        }
    }

    var systemImage: String {
        switch self {
        case .dateAdded:      return "clock"
        case .authorLastName: return "person"
        case .title:          return "textformat"
        case .year:           return "calendar"
        }
    }

    /// Returns `books` sorted for this order.
    func sorted(_ books: [Book]) -> [Book] {
        switch self {
        case .dateAdded:
            return books.sorted {
                ($0.dateAdded ?? .distantPast) > ($1.dateAdded ?? .distantPast)
            }
        case .authorLastName:
            return books.sorted {
                $0.authorSort.localizedCaseInsensitiveCompare($1.authorSort) == .orderedAscending
            }
        case .title:
            return books.sorted {
                $0.titleSort.localizedCaseInsensitiveCompare($1.titleSort) == .orderedAscending
            }
        case .year:
            return books.sorted {
                ($0.publicationYear ?? Int.min) > ($1.publicationYear ?? Int.min)
            }
        }
    }
}
