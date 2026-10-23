import AVFoundation
import SwiftUI
import UIKit

/// Clip within the upright source's fitted rectangle; the surrounding letterbox never scales.
struct ClipFramingViewport<Content: View>: View {
    let sourceSize: CGSize
    let framing: ClipFraming
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            let fit = ClipFramingGeometry.aspectFitRect(sourceSize: sourceSize, in: CGRect(origin: .zero, size: proxy.size))
            let effective = framing.normalized
            content()
                .frame(width: fit.width, height: fit.height)
                .scaleEffect(effective.scale)
                .offset(x: (0.5 - effective.centerX) * effective.scale * fit.width,
                        y: (0.5 - effective.centerY) * effective.scale * fit.height)
                .frame(width: fit.width, height: fit.height)
                .clipped()
                .position(x: fit.midX, y: fit.midY)
        }
    }
}

struct ClipFramingPlaybackView: View {
    let player: AVPlayer
    let sourceSize: CGSize?
    let framing: ClipFraming
    let isEnabled: Bool
    let onInteractionBegan: () -> Void
    let onChange: (ClipFraming) -> Void

    @GestureState private var isPinchActive = false
    @GestureState private var isDragActive = false
    @State private var pinchStartScale: Double?
    @State private var dragStartFraming: ClipFraming?

    var body: some View {
        GeometryReader { proxy in
            let size = sourceSize ?? CGSize(width: 16, height: 9)
            let fit = ClipFramingGeometry.aspectFitRect(sourceSize: size, in: CGRect(origin: .zero, size: proxy.size))
            ZStack {
                accessibleBackground
                ClipFramingViewport(sourceSize: size, framing: framing) {
                    ClipPlayerSurface(player: player)
                        .accessibilityHidden(true)
                }
                .accessibilityHidden(true)
                Color.clear
                    .frame(width: fit.width, height: fit.height)
                    .contentShape(Rectangle())
                    .gesture(MagnifyGesture()
                        .updating($isPinchActive) { _, active, _ in active = true }
                        .onChanged { value in
                            guard isEnabled else { return }
                            if pinchStartScale == nil {
                                pinchStartScale = framing.scale
                                onInteractionBegan()
                            }
                            onChange(ClipFraming(scale: (pinchStartScale ?? framing.scale) * value.magnification,
                                centerX: framing.centerX, centerY: framing.centerY))
                        }
                        .onEnded { _ in pinchStartScale = nil })
                    .simultaneousGesture(DragGesture(minimumDistance: 3)
                        .updating($isDragActive) { _, active, _ in active = true }
                        .onChanged { value in
                            guard isEnabled, fit.width > 0, fit.height > 0 else { return }
                            if dragStartFraming == nil {
                                dragStartFraming = framing
                                onInteractionBegan()
                            }
                            let baseline = dragStartFraming ?? framing
                            onChange(ClipFraming(scale: framing.scale,
                                centerX: baseline.centerX - value.translation.width / (framing.scale * fit.width),
                                centerY: baseline.centerY - value.translation.height / (framing.scale * fit.height)))
                        }
                        .onEnded { _ in dragStartFraming = nil })
                    .position(x: fit.midX, y: fit.midY)
                    .allowsHitTesting(isEnabled)
                    .accessibilityHidden(true)
            }
        }
        .onChange(of: isPinchActive) { _, active in if !active { pinchStartScale = nil } }
        .onChange(of: isDragActive) { _, active in if !active { dragStartFraming = nil } }
        .onChange(of: isEnabled) { _, enabled in
            if !enabled { pinchStartScale = nil; dragStartFraming = nil }
        }
    }

    // Keep accessibility bounds independent of transformed player-layer descendants.
    private var accessibleBackground: some View {
        Color.black
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("片段播放预览")
            .accessibilityIdentifier("ClipFramingPreview")
            .accessibilityValue(String(format: "%.1f 倍，取景中心横向 %.0f%%，纵向 %.0f%%", framing.scale, framing.centerX * 100, framing.centerY * 100))
            .accessibilityHint(isEnabled ? "双指缩放、拖动调整取景，也可使用调整和方向操作" : "视频载入后可调整取景")
            .accessibilityAdjustableAction { direction in
                guard isEnabled else { return }
                let delta = direction == .increment ? 0.1 : -0.1
                adjust(ClipFraming(scale: framing.scale + delta, centerX: framing.centerX, centerY: framing.centerY))
            }
            .accessibilityAction(named: Text("向左移动取景")) { move(x: -1, y: 0) }
            .accessibilityAction(named: Text("向右移动取景")) { move(x: 1, y: 0) }
            .accessibilityAction(named: Text("向上移动取景")) { move(x: 0, y: -1) }
            .accessibilityAction(named: Text("向下移动取景")) { move(x: 0, y: 1) }
    }

    private func move(x: Double, y: Double) {
        guard isEnabled else { return }
        adjust(ClipFraming(scale: framing.scale, centerX: framing.centerX + x * 0.05 / framing.scale,
            centerY: framing.centerY + y * 0.05 / framing.scale))
    }

    private func adjust(_ value: ClipFraming) {
        onInteractionBegan()
        let normalized = value.normalized
        onChange(normalized)
        UIAccessibility.post(notification: .announcement, argument: normalized == framing ? "已到取景边界" : "已调整取景")
    }
}

private struct ClipPlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> ClipPlayerLayerView {
        let view = ClipPlayerLayerView()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: ClipPlayerLayerView, context: Context) {
        uiView.playerLayer.player = player
    }

    static func dismantleUIView(_ uiView: ClipPlayerLayerView, coordinator: Void) {
        uiView.playerLayer.player = nil
    }
}

private final class ClipPlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
