import SwiftUI

/// A single cover in the grid. Loads its thumbnail lazily and shows a titled
/// placeholder while loading or when no cover exists.
struct BookCoverCell: View {
    let book: Book
    let libraryRoot: String

    @State private var image: UIImage?
    @State private var didAttempt = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.secondarySystemBackground))

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    placeholder
                }
            }
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.black.opacity(0.08))
            )
            .shadow(color: .black.opacity(0.15), radius: 3, y: 2)

            Text(book.title)
                .font(.caption2)
                .lineLimit(2)
                .foregroundStyle(.primary)
            Text(book.displayAuthors)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
        .task(id: book.id) { await loadCover() }
    }

    private var placeholder: some View {
        VStack(spacing: 4) {
            Image(systemName: book.hasCover ? "book.closed" : "book")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(book.title)
                .font(.system(size: 9))
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private func loadCover() async {
        guard image == nil, !didAttempt else { return }
        didAttempt = true
        let loaded = await CoverCache.shared.image(for: book, libraryRoot: libraryRoot)
        if let loaded { withAnimation(.easeIn(duration: 0.2)) { image = loaded } }
    }
}
