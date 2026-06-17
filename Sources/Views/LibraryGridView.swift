import SwiftUI

/// The main screen: a searchable grid of every cover in the library.
///
/// Uses `LazyVGrid` inside a `ScrollView` so only on-screen cells exist; covers
/// load lazily through `CoverCache`. This keeps 7,000+ titles smooth.
struct LibraryGridView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedBook: Book?
    @State private var showSignOutConfirm = false

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 140), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(appState.filteredBooks) { book in
                        BookCoverCell(book: book, libraryRoot: appState.config?.rootPath ?? "")
                            .onTapGesture { selectedBook = book }
                    }
                }
                .padding(16)
            }
            .overlay {
                if appState.filteredBooks.isEmpty {
                    ContentUnavailableCompat(
                        title: appState.books.isEmpty ? "No Books Yet" : "No Matches",
                        systemImage: "books.vertical",
                        description: appState.books.isEmpty
                            ? "Pull to refresh to load your library."
                            : "Try a different title or author."
                    )
                }
            }
            .navigationTitle("Big Bookshelf")
            .searchable(text: $appState.searchText, prompt: "Search title or author")
            .refreshable { await appState.sync() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            Task { await appState.sync(force: true) }
                        } label: {
                            Label("Refresh Catalog", systemImage: "arrow.clockwise")
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
            }
            .sheet(item: $selectedBook) { book in
                BookDetailView(book: book)
            }
            .confirmationDialog("Sign out of Dropbox and clear the local catalog?",
                                isPresented: $showSignOutConfirm, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) { appState.signOut() }
                Button("Cancel", role: .cancel) {}
            }
        }
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
