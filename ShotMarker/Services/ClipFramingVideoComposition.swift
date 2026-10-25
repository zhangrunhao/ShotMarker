import AVFoundation
import CoreImage
import CoreGraphics

/// Immutable source geometry and output timing captured while assembling the movie.
struct ClipFramingVideoSegment {
    let timeRange: CMTimeRange
    let naturalSize: CGSize
    let preferredTransform: CGAffineTransform
    let framing: ClipFraming
    let label: String
    let markerLabelPlacement: MarkerLabelPlacement?

    init(timeRange: CMTimeRange, naturalSize: CGSize, preferredTransform: CGAffineTransform,
         framing: ClipFraming, label: String, markerLabelPlacement: MarkerLabelPlacement? = nil) {
        self.timeRange = timeRange
        self.naturalSize = naturalSize
        self.preferredTransform = preferredTransform
        self.framing = framing
        self.label = label
        self.markerLabelPlacement = markerLabelPlacement
    }

    var uprightBounds: CGRect {
        ClipFramingGeometry.uprightBounds(naturalSize: naturalSize, preferredTransform: preferredTransform)
    }
}

enum ClipFramingVideoComposition {
    static func make(
        for asset: AVAsset,
        track: AVAssetTrack,
        segments: [ClipFramingVideoSegment],
        style: MarkerLabelStyle,
    ) async throws -> AVVideoComposition {
        guard let first = segments.first else { throw VideoClipEditingError.emptySegments }
        let canvas = CGRect(origin: .zero, size: first.uprightBounds.size)
        guard canvas.width.isFinite, canvas.height.isFinite, canvas.width > 0, canvas.height > 0 else {
            throw VideoClipEditingError.missingVideoTrack
        }
        var images: [MarkerLabelImageKey: CGImage] = [:]
        var configuration = try await AVVideoComposition.Configuration(for: asset)
        configuration.renderSize = canvas.size
        configuration.renderScale = 1
        configuration.customVideoCompositorClass = ClipFramingVideoCompositor.self
        configuration.instructions = try segments.map { segment in
            let bounds = segment.uprightBounds
            guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0,
                  segment.framing.isValid
            else { throw VideoClipEditingError.missingVideoTrack }
            let upright = segment.preferredTransform.concatenating(
                CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY)
            )
            let crop = ClipFramingGeometry.cropRect(
                framing: segment.framing, in: CGRect(origin: .zero, size: bounds.size)
            )
            let fitted = ClipFramingGeometry.aspectFitRect(sourceSize: bounds.size, in: canvas)
            let rawToCanvas = upright
                .concatenating(CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
                .concatenating(CGAffineTransform(scaleX: fitted.width / crop.width, y: fitted.height / crop.height))
                .concatenating(CGAffineTransform(translationX: fitted.minX, y: fitted.minY))
            let rawCrop = crop.applying(upright.inverted())
            let flipSource = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: segment.naturalSize.height)
            let flipCanvas = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: canvas.height)
            let segmentStyle = (segment.markerLabelPlacement?.applying(to: style) ?? style).normalized
            let image: CIImage?
            let labelOrigin: CGPoint
            if segmentStyle.textOpacity > 0 || segmentStyle.backgroundOpacity > 0 {
                let key = MarkerLabelImageKey(text: segment.label, canvasSize: canvas.size, style: segmentStyle)
                let render: MarkerLabelRender
                if let cached = images[key] {
                    render = MarkerLabelRendering.layout(image: cached, canvasSize: canvas.size, style: segmentStyle)
                } else {
                    render = try MarkerLabelRendering.make(text: segment.label, canvasSize: canvas.size, style: segmentStyle)
                    images[key] = render.image
                }
                image = CIImage(cgImage: render.image)
                labelOrigin = render.coreImageOrigin
            } else {
                image = nil
                labelOrigin = .zero
            }
            return ClipFramingVideoInstruction(
                timeRange: segment.timeRange,
                trackID: track.trackID,
                rawCrop: rawCrop.applying(flipSource),
                transform: flipSource.concatenating(rawToCanvas).concatenating(flipCanvas),
                canvas: canvas,
                labelImage: image?.transformed(by: CGAffineTransform(translationX: labelOrigin.x, y: labelOrigin.y))
            )
        }
        return AVVideoComposition(configuration: configuration)
    }
}

/// Position changes reuse pixels; every property affecting those pixels belongs in the key.
nonisolated private struct MarkerLabelImageKey: Hashable {
    let text: String
    let canvasWidth: CGFloat
    let canvasHeight: CGFloat
    let fontSizeRatio: Double
    let textOpacity: Double
    let backgroundOpacity: Double

    init(text: String, canvasSize: CGSize, style: MarkerLabelStyle) {
        self.text = text
        canvasWidth = canvasSize.width
        canvasHeight = canvasSize.height
        fontSizeRatio = style.fontSizeRatio
        textOpacity = style.textOpacity
        backgroundOpacity = style.backgroundOpacity
    }
}

/// Passthrough must stay disabled: even an original framing needs this source's direction and canvas fit.
nonisolated private final class ClipFramingVideoInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = false
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let trackID: CMPersistentTrackID
    let rawCrop: CGRect
    let transform: CGAffineTransform
    let canvas: CGRect
    let labelImage: CIImage?

    init(timeRange: CMTimeRange, trackID: CMPersistentTrackID, rawCrop: CGRect,
         transform: CGAffineTransform, canvas: CGRect, labelImage: CIImage?) {
        self.timeRange = timeRange
        self.trackID = trackID
        requiredSourceTrackIDs = [NSNumber(value: trackID)]
        self.rawCrop = rawCrop
        self.transform = transform
        self.canvas = canvas
        self.labelImage = labelImage
    }
}

/// AVFoundation converts unsupported HDR/wide-color input to SDR before supplying these BGRA frames.
/// Rendering and label selection use immutable instruction data, never a mutable task or editor.
nonisolated final class ClipFramingVideoCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    let sourcePixelBufferAttributes: [String: any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ]
    let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ]
    private let queue = DispatchQueue(label: "ShotMarker.clip-framing-render")
    private let context = CIContext()
    private let pendingLock = NSRecursiveLock()
    private var pending: [UUID: AVAsynchronousVideoCompositionRequest] = [:]

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        let token = UUID()
        pendingLock.lock()
        pending[token] = request
        pendingLock.unlock()
        queue.async { [self] in
            pendingLock.lock()
            guard pending[token] != nil else { pendingLock.unlock(); return }
            // Capture every request-owned resource before cancellation can finish the request.
            // Retained pixel buffers and immutable instructions can outlive its callback.
            guard let instruction = request.videoCompositionInstruction as? ClipFramingVideoInstruction,
                  let source = request.sourceFrame(byTrackID: instruction.trackID),
                  let output = request.renderContext.newPixelBuffer()
            else {
                finish(token) { $0.finish(with: VideoClipEditingError.exportFailed) }
                pendingLock.unlock()
                return
            }
            let sourceImage = CIImage(cvPixelBuffer: source)
                .cropped(to: instruction.rawCrop)
                .transformed(by: instruction.transform)
            pendingLock.unlock()
            var image = sourceImage.composited(over: CIImage(color: .black).cropped(to: instruction.canvas))
            if let label = instruction.labelImage { image = label.composited(over: image) }
            context.render(image, to: output, bounds: instruction.canvas, colorSpace: CGColorSpaceCreateDeviceRGB())
            finish(token) { $0.finish(withComposedVideoFrame: output) }
        }
    }

    func cancelAllPendingVideoCompositionRequests() {
        // Finish every owned request synchronously before returning. A render already in progress
        // may finish its pixels, but can no longer finish the cancelled request a second time.
        pendingLock.lock()
        let requests = Array(pending.values)
        pending.removeAll()
        for request in requests { request.finishCancelledRequest() }
        pendingLock.unlock()
    }

    private func finish(_ token: UUID, using completion: (AVAsynchronousVideoCompositionRequest) -> Void) {
        pendingLock.lock()
        if let request = pending.removeValue(forKey: token) { completion(request) }
        pendingLock.unlock()
    }
}
