import SwiftyDropbox
import UIKit

/// The single place that knows which OAuth scopes the app needs and how to
/// start the (re-)link flow.
///
/// `files.content.write` exists only so new books can be uploaded into the
/// inbox folder; everything else the app does is read-only.
enum DropboxAuth {
    static let scopes = [
        "account_info.read",
        "files.metadata.read",
        "files.content.read",
        "files.content.write",
    ]

    /// Starts the Dropbox OAuth flow (PKCE; no secret in the app). Also used
    /// to re-link an account whose token predates the upload scope —
    /// `includeGrantedScopes` keeps what was already granted and adds the rest.
    @MainActor
    static func startAuthFlow() {
        guard let controller = UIApplication.shared.topViewController else { return }
        let scopeRequest = ScopeRequest(
            scopeType: .user,
            scopes: scopes,
            includeGrantedScopes: true
        )
        DropboxClientsManager.authorizeFromControllerV2(
            UIApplication.shared,
            controller: controller,
            loadingStatusDelegate: nil,
            openURL: { url in UIApplication.shared.open(url) },
            scopeRequest: scopeRequest
        )
    }
}
