import SwiftUI

#if os(iOS)
    import UIKit

    struct AppLogShareSheet: UIViewControllerRepresentable {
        let fileURL: URL

        func makeUIViewController(context: Context) -> UIActivityViewController {
            UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        }

        func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
    }
#endif
