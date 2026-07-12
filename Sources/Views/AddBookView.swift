import SwiftUI
import UniformTypeIdentifiers

/// "Add to Library": pick book files with the system Files picker, upload
/// them to the Dropbox inbox folder, and watch for desktop Calibre's
/// automatic adding to import them into the library.
struct AddBookView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// One picked file moving through the sequential upload queue.
    struct UploadItem: Identifiable, Equatable {
        let id = UUID()
        /// A staged private copy under tmp/InboxStaging/<uuid>/, so uploads
        /// (and re-auth retries) don't depend on the security-scoped original.
        let localURL: URL
        var state: State

        var name: String { localURL.lastPathComponent }

        enum State: Equatable {
            case waiting
            case uploading(Double)
            case done
            case failed(String)
        }
    }

    @State private var uploads: [UploadItem] = []
    @State private var isUploading = false
    @State private var showImporter = false
    @State private var showInboxPicker = false
    @State private var showReauthPrompt = false
    @State private var importError: String?

    /// Formats Calibre commonly imports. EPUB and PDF have system UTTypes;
    /// the rest are matched by filename extension, so no Info.plist
    /// declarations are needed.
    private static let ebookTypes: [UTType] =
        [.epub, .pdf] + ["mobi", "azw3", "azw", "cbz", "cbr", "fb2", "txt", "rtf", "docx"]
            .compactMap { UTType(filenameExtension: $0) }

    var body: some View {
        NavigationStack {
            List {
                chooseSection
                if !uploads.isEmpty {
                    uploadsSection
                }
                pendingSection
                inboxFolderSection
            }
            .navigationTitle("Add to Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .refreshable { await appState.refreshInbox() }
            .task { await appState.refreshInbox() }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: Self.ebookTypes,
                          allowsMultipleSelection: true) { result in
                handlePicked(result)
            }
            .sheet(isPresented: $showInboxPicker) {
                NavigationStack {
                    FolderPickerView(
                        title: "Choose Inbox",
                        footer: "New books upload here for Calibre to import. Pick a folder outside your Calibre library."
                    ) { path in
                        appState.setInboxPath(path)
                        showInboxPicker = false
                    }
                }
            }
            .alert("Permission Needed", isPresented: $showReauthPrompt) {
                Button("Re-connect Dropbox") { DropboxAuth.startAuthFlow() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Uploading needs a Dropbox permission this sign-in doesn't have yet. Re-connect to grant it — queued files resume automatically.")
            }
            .alert("Couldn't Add Files", isPresented: .constant(importError != nil)) {
                Button("OK") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
            .onReceive(NotificationCenter.default.publisher(for: .dropboxDidAuthorize)) { _ in
                // Re-linked with the upload scope: resume anything still queued.
                startUploadsIfNeeded()
            }
        }
    }

    // MARK: - Sections

    private var chooseSection: some View {
        Section {
            Button {
                showImporter = true
            } label: {
                Label("Choose Files…", systemImage: "plus.circle.fill")
            }
        } footer: {
            Text("Files upload to “\(appState.inboxPath ?? "")” in Dropbox. Desktop Calibre imports them automatically next time it runs, and they appear on your shelf after the next catalog refresh.")
        }
    }

    private var uploadsSection: some View {
        Section("Uploads") {
            ForEach(uploads) { item in
                uploadRow(item)
            }
        }
    }

    private var pendingSection: some View {
        Section {
            if appState.pendingInboxFiles.isEmpty {
                Text("Nothing waiting.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appState.pendingInboxFiles) { file in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.name).lineLimit(1)
                        Text("\(ByteCountFormatter.string(fromByteCount: Int64(file.sizeBytes), countStyle: .file)) · \(file.serverModified.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Waiting for Calibre")
        } footer: {
            Text("These are in the inbox but not imported yet. They disappear from here — and appear on the shelf — after desktop Calibre runs and the catalog refreshes.")
        }
    }

    private var inboxFolderSection: some View {
        Section {
            Button {
                showInboxPicker = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Inbox Folder")
                            .foregroundStyle(.primary)
                        Text(appState.inboxPath ?? "—")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Change")
                }
            }
        } footer: {
            Text("Point desktop Calibre's automatic adding (Preferences → Adding books) at this folder's synced copy. It must be outside the Calibre library folder.")
        }
    }

    private func uploadRow(_ item: UploadItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).lineLimit(1)
                if case .done = item.state {
                    Text("Queued for Calibre")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if case .failed(let message) = item.state {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            Spacer()
            switch item.state {
            case .waiting:
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
            case .uploading(let fraction):
                HStack(spacing: 8) {
                    ProgressView(value: fraction)
                        .frame(width: 80)
                    Text("\(Int(fraction * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed:
                Button {
                    retry(item.id)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Picking & staging

    @MainActor
    private func handlePicked(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            var unreadable: [String] = []
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else {
                    unreadable.append(url.lastPathComponent)
                    continue
                }
                defer { url.stopAccessingSecurityScopedResource() }
                do {
                    let staged = try stage(url)
                    uploads.append(UploadItem(localURL: staged, state: .waiting))
                } catch {
                    unreadable.append(url.lastPathComponent)
                }
            }
            if !unreadable.isEmpty {
                importError = "Couldn't read: \(unreadable.joined(separator: ", "))"
            }
            startUploadsIfNeeded()
        }
    }

    /// Copies a picked file into a private per-item staging folder.
    private func stage(_ url: URL) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("InboxStaging", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let destination = dir.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }

    // MARK: - Upload queue

    @MainActor
    private func startUploadsIfNeeded() {
        guard !isUploading else { return }
        isUploading = true
        Task {
            await runUploadQueue()
            isUploading = false
        }
    }

    @MainActor
    private func runUploadQueue() async {
        while let index = uploads.firstIndex(where: { $0.state == .waiting }) {
            let item = uploads[index]
            update(item.id, to: .uploading(0))
            do {
                try await appState.uploadToInbox(localURL: item.localURL) { fraction in
                    update(item.id, to: .uploading(fraction))
                }
                update(item.id, to: .done)
                try? FileManager.default.removeItem(at: item.localURL.deletingLastPathComponent())
            } catch DropboxError.missingScope {
                // Token predates the upload scope: keep the item queued and
                // ask for a re-link; .dropboxDidAuthorize resumes the queue.
                update(item.id, to: .waiting)
                showReauthPrompt = true
                return
            } catch {
                update(item.id, to: .failed(error.localizedDescription))
            }
        }
    }

    @MainActor
    private func retry(_ id: UUID) {
        update(id, to: .waiting)
        startUploadsIfNeeded()
    }

    @MainActor
    private func update(_ id: UUID, to state: UploadItem.State) {
        guard let index = uploads.firstIndex(where: { $0.id == id }) else { return }
        uploads[index].state = state
    }
}
