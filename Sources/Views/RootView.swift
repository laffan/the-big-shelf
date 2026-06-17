import SwiftUI

/// Routes between onboarding and the library based on app state.
struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            switch appState.phase {
            case .onboarding:
                OnboardingView()
            case .syncing(let message):
                SyncingView(message: message)
            case .ready:
                LibraryGridView()
            case .failed(let message):
                ErrorView(message: message) {
                    Task { await appState.sync(force: true) }
                }
            }
        }
        .onAppear { appState.bootstrap() }
    }
}

struct SyncingView: View {
    let message: String

    var body: some View {
        VStack(spacing: 18) {
            ProgressView()
                .scaleEffect(1.4)
            Text(message)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("Something went wrong")
                .font(.title3.bold())
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try Again", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
