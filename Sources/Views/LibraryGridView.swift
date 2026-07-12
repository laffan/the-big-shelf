import SwiftUI

/// The main screen: a searchable grid of every cover in the library.
///
/// Uses `LazyVGrid` inside a `ScrollView` so only on-screen cells exist; covers
/// load lazily through `CoverCache`. This keeps 7,000+ titles smooth.
struct LibraryGridView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedBook: Book?
    @State private var showSignOutConfirm = false
    @State private var showAddBook = false

    /// Number of cover columns (zoom level), persisted across launches.
    @AppStorage("BigBookshelf.ColumnCount") private var columnCount: Int = 4

    private static let minColumns = 3
    private static let maxColumns = 8

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 14), count: columnCount)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(appState.displayedBooks) { book in
                        BookCoverCell(book: book,
                                      libraryRoot: appState.config?.rootPath ?? "",
                                      compact: columnCount >= 6)
                            .onTapGesture { selectedBook = book }
                    }
                }
                .padding(16)
                .animation(.default, value: columnCount)
            }
            .overlay {
                if appState.displayedBooks.isEmpty {
                    ContentUnavailableCompat(
                        title: appState.books.isEmpty ? "No Books Yet" : "No Matches",
                        systemImage: "books.vertical",
                        description: appState.books.isEmpty
                            ? "Pull to refresh to load your library."
                            : "Try a different title or author."
                    )
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let caching = appState.coverCaching {
                    coverCachingBanner(caching)
                }
            }
            .navigationTitle("Big Bookshelf")
            .searchable(text: $appState.searchText, prompt: "Search title or author")
            .refreshable { await appState.sync() }
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        columnCount = min(Self.maxColumns, columnCount + 1)
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .disabled(columnCount >= Self.maxColumns)

                    Button {
                        columnCount = max(Self.minColumns, columnCount - 1)
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .disabled(columnCount <= Self.minColumns)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    addBookButton
                    menu
                }
            }
            .sheet(item: $selectedBook) { book in
                BookDetailView(book: book)
            }
            .sheet(isPresented: $showAddBook) {
                AddBookView()
            }
            .confirmationDialog("Sign out of Dropbox and clear the local catalog and downloads?",
                                isPresented: $showSignOutConfirm, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) { appState.signOut() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    /// Opens the "Add to Library" sheet; a small dot marks files still
    /// waiting in the inbox for desktop Calibre to import.
    private var addBookButton: some View {
        Button {
            showAddBook = true
        } label: {
            Image(systemName: "plus")
                .overlay(alignment: .topTrailing) {
                    if !appState.pendingInboxFiles.isEmpty {
                        Circle()
                            .fill(.orange)
                            .frame(width: 8, height: 8)
                            .offset(x: 5, y: -5)
                    }
                }
        }
    }

    private var menu: some View {
        Menu {
            Picker("Sort By", selection: $appState.sortOrder) {
                ForEach(LibrarySortOrder.allCases) { order in
                    Label(order.label, systemImage: order.systemImage).tag(order)
                }
            }

            Divider()

            Button {
                Task { await appState.sync(force: true) }
            } label: {
                Label("Refresh Catalog", systemImage: "arrow.clockwise")
            }

            if !appState.pendingInboxFiles.isEmpty {
                Text("\(appState.pendingInboxFiles.count) waiting for Calibre")
            }

            if appState.coverCaching == nil {
                Button {
                    appState.cacheAllCovers()
                } label: {
                    Label("Save All Covers", systemImage: "square.and.arrow.down.on.square")
                }
            } else {
                Button(role: .destructive) {
                    appState.cancelCoverCaching()
                } label: {
                    Label("Stop Saving Covers", systemImage: "stop.circle")
                }
            }

            if let synced = appState.config?.lastSynced {
                Text("Last synced \(synced.formatted(date: .abbreviated, time: .shortened))")
            }

            Divider()

            Button(role: .destructive) {
                showSignOutConfirm = true
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    private func coverCachingBanner(_ caching: AppState.CoverCachingState) -> some View {
        HStack(spacing: 12) {
            ProgressView(value: caching.fraction)
                .frame(maxWidth: .infinity)
            Text("\(caching.done)/\(caching.total)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Button {
                appState.cancelCoverCaching()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

/// Lightweight stand-in for `ContentUnavailableView` (iOS 17+) so we keep an
/// iOS 16 deployment target.
struct ContentUnavailableCompat: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(title).font(.title3.bold())
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
