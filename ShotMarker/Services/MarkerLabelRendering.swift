import CoreGraphics
import UIKit

/// The native canvas image and geometry shared by the editor and final movie.
struct MarkerLabelRender {
    let image: CGImage
    let size: CGSize
    let frame: CGRect
    let coreImageOrigin: CGPoint
}

enum MarkerLabelRendering {
    static func make(text: String, canvasSize: CGSize, style: MarkerLabelStyle) throws -> MarkerLabelRender {
        let metrics = try HighlightClipMarkerLabelOverlayMetrics.make(renderSize: canvasSize, style: style)
        guard let image = VideoClipEditingService.makeMarkerLabelOverlayImage(text: text, metrics: metrics) else {
            throw VideoClipEditingError.exportFailed
        }
        return layout(image: image, canvasSize: canvasSize, style: style)
    }

    static func layout(image: CGImage, canvasSize: CGSize, style: MarkerLabelStyle) -> MarkerLabelRender {
        let normalized = style.normalized
        let size = CGSize(width: image.width, height: image.height)
        let canvas = CGRect(origin: .zero, size: canvasSize)
        let center = CGPoint(x: normalized.normalizedCenterX, y: normalized.normalizedCenterY)
        return MarkerLabelRender(
            image: image,
            size: size,
            frame: CGRect(origin: MarkerLabelLayout.clampedOrigin(for: center, labelSize: size, in: canvas), size: size),
            coreImageOrigin: MarkerLabelLayout.coreImageOrigin(for: center, labelSize: size, in: canvas)
        )
    }
}
