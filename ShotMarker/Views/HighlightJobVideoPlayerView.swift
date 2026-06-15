#if os(iOS)
    import AVKit
    import SwiftUI

    struct HighlightJobVideoPlayerView: UIViewControllerRepresentable {
        let videoURL: URL

        func makeUIViewController(context: Context) -> AVPlayerViewController {
            let controller = AVPlayerViewController()
            controller.player = AVPlayer(url: videoURL)
            return controller
        }

        func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
            if (uiViewController.player?.currentItem?.asset as? AVURLAsset)?.url != videoURL {
                uiViewController.player = AVPlayer(url: videoURL)
            }
        }
    }
#endif
