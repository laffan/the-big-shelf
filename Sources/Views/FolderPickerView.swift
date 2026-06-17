import SwiftUI

/// Lets the user navigate their Dropbox folders and pick the Calibre library
/// root (the folder that contains `metadata.db`). Each level pushes a fresh
/// instance seeded with that folder's path.
struct FolderPickerView: View {
    let initialPath: String                  // "" == Dropbox root
    let onChoose: (String) -> Void

    @State private var folders: [DropboxFolderEntry] = []
    @State private var isLoading = true
    @State private var loadError: String?

    init(initialPath: String = "", onChoose: @escaping (String) -> Void) {
        self.initialPath = initialPath
        self.onChoose = onChoose
    }

    private var displayPath: String { initialPath.isEmpty ? "Dropbox" : initialPath }

    var body: some View {
        List {
            Section {
                if isLoading {
                    HStack { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
                } else if let loadError {
                    Text(loadError).foregroundStyle(.red)
                } else if folders.isEmpty {
                    Text("No sub-folders here.").foregroundStyle(.secondary)
                } else {
                    ForEach(folders) { folder in
                        NavigationLink(value: folder) {
                            Label(folder.name, systemImage: "folder")
                        }
                    }
                }
            } header: {
                Text("Folders in \(displayPath)")
            } footer: {
                Text("Navigate to your Calibre library folder (the one containing metadata.db), then tap “Use This Folder”.")
            }
        }
        .navigationTitle("Choose Library")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: DropboxFolderEntry.self) { folder in
            FolderPickerView(initialPath: folder.pathLower, onChoose: onChoose)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                onChoose(initialPath)
            } label: {
                Label("Use This Folder", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
            .background(.bar)
        }
        .task { await reload() }
    }

    private func reload() async {
        isLoading = true
        loadError = nil
        do {
            folders = try await DropboxService.shared.listFolders(path: initialPath)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
