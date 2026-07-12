import SwiftUI

/// One-time setup: connect Dropbox, then choose the Calibre library folder.
struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isAuthorized = DropboxService.shared.isAuthorized
    @State private var authError: String?

    var body: some View {
        NavigationStack {
            if isAuthorized {
                FolderPickerView { chosenRoot in
                    appState.completeOnboarding(rootPath: chosenRoot)
                }
            } else {
                connectScreen
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dropboxDidAuthorize)) { _ in
            isAuthorized = DropboxService.shared.isAuthorized
            authError = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .dropboxDidFailAuthorize)) { _ in
            authError = "Dropbox sign-in was cancelled or failed. Please try again."
        }
    }

    private var connectScreen: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("The Big Bookshelf")
                .font(.largeTitle.bold())
            Text("Browse your entire Calibre library from Dropbox and send any book to Apple Books.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if DropboxService.appKey == nil {
                Label("Dropbox app key not configured.\nSee Config/Secrets.xcconfig.",
                      systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }

            if let authError {
                Text(authError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
            Button(action: startDropboxAuth) {
                Label("Connect Dropbox", systemImage: "link")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(DropboxService.appKey == nil)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    private func startDropboxAuth() {
        DropboxAuth.startAuthFlow()
    }
}
