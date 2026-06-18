import Foundation

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

    /// Returns a comparator that sorts `Book`s for this order.
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
