import Foundation
import GRDB

/// Reads a Calibre `metadata.db` (a standard SQLite database) that has been
/// downloaded from Dropbox to the device.
///
/// This is the core of the "works on huge libraries" strategy: rather than
/// walking thousands of Dropbox folders, we read one SQLite file and get every
/// title, author, format and cover flag in a couple of queries.
final class CalibreMetadataReader {
    private let dbQueue: DatabaseQueue

    init(path: String) throws {
        var config = Configuration()
        config.readonly = true
        dbQueue = try DatabaseQueue(path: path, configuration: config)
    }

    /// Loads every book with its authors, ordered by Calibre's title-sort.
    func loadAllBooks() throws -> [Book] {
        try dbQueue.read { db in
            // 1) Authors grouped by book, preserving Calibre's link order.
            let authorRows = try Row.fetchAll(db, sql: """
                SELECT bal.book AS book_id, a.name AS name
                FROM books_authors_link bal
                JOIN authors a ON a.id = bal.author
                ORDER BY bal.id
            """)
            var authorsByBook: [Int64: [String]] = [:]
            for row in authorRows {
                let bookId: Int64 = row["book_id"]
                let name: String = row["name"]
                authorsByBook[bookId, default: []].append(name)
            }

            // 2) The books themselves.
            let bookRows = try Row.fetchAll(db, sql: """
                SELECT id, title, sort, author_sort, path, has_cover,
                       last_modified, timestamp, pubdate
                FROM books
                ORDER BY sort COLLATE NOCASE
            """)

            return bookRows.map { row in
                let id: Int64 = row["id"]
                return Book(
                    id: id,
                    title: row["title"] ?? "Untitled",
                    titleSort: row["sort"] ?? row["title"] ?? "",
                    authors: authorsByBook[id] ?? [],
                    authorSort: row["author_sort"] ?? "",
                    path: row["path"] ?? "",
                    hasCover: ((row["has_cover"] as Int64?) ?? 0) != 0,
                    lastModified: Self.parseDate(row["last_modified"]),
                    dateAdded: Self.parseDate(row["timestamp"]),
                    publicationYear: Self.parseYear(row["pubdate"])
                )
            }
        }
    }

    /// Loads on-demand detail (formats, description, series, tags) for one book.
    func loadDetail(bookId: Int64) throws -> BookDetail {
        try dbQueue.read { db in
            let formatRows = try Row.fetchAll(db, sql: """
                SELECT format, name, uncompressed_size
                FROM data WHERE book = ?
                ORDER BY format
            """, arguments: [bookId])
            let formats = formatRows.map { row in
                BookFormat(format: (row["format"] as String? ?? "").uppercased(),
                           fileName: row["name"] ?? "",
                           sizeBytes: row["uncompressed_size"])
            }

            let comments = try String.fetchOne(db,
                sql: "SELECT text FROM comments WHERE book = ?", arguments: [bookId])

            let tags = try String.fetchAll(db, sql: """
                SELECT t.name FROM books_tags_link btl
                JOIN tags t ON t.id = btl.tag
                WHERE btl.book = ? ORDER BY t.name
            """, arguments: [bookId])

            let seriesRow = try Row.fetchOne(db, sql: """
                SELECT s.name AS name, b.series_index AS idx
                FROM books_series_link bsl
                JOIN series s ON s.id = bsl.series
                JOIN books b ON b.id = bsl.book
                WHERE bsl.book = ?
            """, arguments: [bookId])

            let pubdate = try Row.fetchOne(db,
                sql: "SELECT pubdate FROM books WHERE id = ?", arguments: [bookId])

            return BookDetail(
                comments: comments,
                formats: formats,
                series: seriesRow?["name"],
                seriesIndex: seriesRow?["idx"],
                tags: tags,
                publishedDate: Self.parseDate(pubdate?["pubdate"])
            )
        }
    }

    /// Parses a Calibre timestamp. Calibre stores these as e.g.
    /// "2019-05-04 19:31:00.000000+00:00" — a space (not 'T') between date and
    /// time, often with microsecond precision — which ISO8601DateFormatter
    /// rejects out of the box, so we normalise and fall back as needed.
    private static func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let normalized = value.replacingOccurrences(of: " ", with: "T")

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: normalized) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: normalized) { return date }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        for format in [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ",
            "yyyy-MM-dd'T'HH:mm:ssZZZZZ",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd",
        ] {
            df.dateFormat = format
            if let date = df.date(from: normalized) { return date }
        }
        return nil
    }

    /// Extracts a 4-digit year from a Calibre date string (e.g. "2018-04-01...").
    /// Calibre uses the year 0101 as a "no date" sentinel, which we treat as nil.
    private static func parseYear(_ value: String?) -> Int? {
        guard let value, value.count >= 4 else { return nil }
        guard let year = Int(value.prefix(4)) else { return nil }
        return year <= 101 ? nil : year
    }
}
