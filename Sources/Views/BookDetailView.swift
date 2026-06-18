import SwiftUI

/// Book info, available formats, and download-to-share actions.
struct BookDetailView: View {
    let book: Book

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var detail: BookDetail?
    @State private var cover: UIImage?
    @State private var states: [String: FormatState] = [:]
    @State private var shareURL: URL?
    @State private var downloadError: String?

    /// Per-format download lifecycle.
    enum FormatState: Equatable {
        case idle
        case downloading(Double)
        case downloaded
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if let comments = detail?.comments, !comments.isEmpty {
                        descriptionSection(comments)
                    }
                    formatsSection
                    metadataSection
                }
                .padding(20)
            }
            .navigationTitle(book.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                detail = appState.loadDetail(for: book)
                // Seed each format's state from what's already saved on disk.
                for format in detail?.formats ?? [] {
                    states[format.format] = appState.downloadedURL(for: format, of: book) != nil ? .downloaded : .idle
                }
                cover = await CoverCache.shared.image(for: book, libraryRoot: appState.config?.rootPath ?? "")
            }
            .sheet(item: $shareURL) { url in
                ShareSheet(items: [url])
            }
            .alert("Download Failed", isPresented: .constant(downloadError != nil)) {
                Button("OK") { downloadError = nil }
            } message: {
                Text(downloadError ?? "")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground))
                if let cover {
                    Image(uiImage: cover).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "book.closed").font(.largeTitle).foregroundStyle(.secondary)
                }
            }
            .frame(width: 110, height: 165)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 4, y: 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(book.title).font(.title3.bold())
                Text(book.displayAuthors).font(.subheadline).foregroundStyle(.secondary)
                if let series = detail?.series {
                    let idx = detail?.seriesIndex.map { String(format: "#%g", $0) } ?? ""
                    Text("\(series) \(idx)").font(.footnote).foregroundStyle(.secondary)
                }
                if let pub = detail?.publishedDate {
                    Text(pub.formatted(.dateTime.year())).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private func descriptionSection(_ comments: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Description").font(.headline)
            // Calibre stores HTML; strip tags for a clean plain-text summary.
            Text(comments.strippingHTML)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var formatsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Available Formats").font(.headline)
            let formats = detail?.formats ?? []
            if formats.isEmpty {
                Text("No downloadable formats found.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(formats) { format in
                    formatRow(format)
                }
            }
        }
    }

    private func formatRow(_ format: BookFormat) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(format.format).font(.body.weight(.medium))
                if let size = format.sizeBytes {
                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            formatActions(format)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func formatActions(_ format: BookFormat) -> some View {
        switch states[format.format] ?? .idle {
        case .idle:
            Button {
                Task { await download(format) }
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.bordered)

        case .downloading(let fraction):
            HStack(spacing: 8) {
                ProgressView(value: fraction)
                    .frame(width: 90)
                Text("\(Int(fraction * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

        case .downloaded:
            HStack(spacing: 8) {
                Button {
                    if let url = appState.downloadedURL(for: format, of: book) {
                        shareURL = url
                    }
                } label: {
                    Label("Send", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive) {
                    appState.deleteDownload(format, of: book)
                    states[format.format] = .idle
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var metadataSection: some View {
        Group {
            if let tags = detail?.tags, !tags.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tags").font(.headline)
                    Text(tags.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func download(_ format: BookFormat) async {
        states[format.format] = .downloading(0)
        do {
            _ = try await appState.downloadFormat(format, of: book) { fraction in
                states[format.format] = .downloading(fraction)
            }
            states[format.format] = .downloaded
        } catch {
            states[format.format] = .idle
            downloadError = error.localizedDescription
        }
    }
}

/// Allows presenting a downloaded file URL via `.sheet(item:)`.
extension URL: Identifiable {
    public var id: String { absoluteString }
}

private extension String {
    /// Very small HTML-to-text cleanup for Calibre comment fields.
    var strippingHTML: String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
