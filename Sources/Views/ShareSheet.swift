import SwiftUI
import UIKit

/// Bridges `UIActivityViewController` into SwiftUI. This is what surfaces the
/// system share sheet, including "Copy to Books" for EPUB/PDF files.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
