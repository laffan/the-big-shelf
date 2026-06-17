import SwiftUI
import SwiftyDropbox

@main
struct BigBookshelfApp: App {
    @StateObject private var appState = AppState()

    init() {
        DropboxService.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .onOpenURL { url in
                    // Completes the Dropbox OAuth round-trip.
                    _ = DropboxClientsManager.handleRedirectURL(url, includeBackgroundTasks: true) { result in
                        switch result {
                        case .success:
                            NotificationCenter.default.post(name: .dropboxDidAuthorize, object: nil)
                        default:
                            NotificationCenter.default.post(name: .dropboxDidFailAuthorize, object: nil)
                        }
                    }
                }
        }
    }
}

extension Notification.Name {
    static let dropboxDidAuthorize = Notification.Name("dropboxDidAuthorize")
    static let dropboxDidFailAuthorize = Notification.Name("dropboxDidFailAuthorize")
}
