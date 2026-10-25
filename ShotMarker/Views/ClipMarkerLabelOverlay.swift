import SwiftUI
import UIKit

/// The same raster label and canvas geometry are used by the movie compositor.
struct ClipMarkerLabelOverlay: View {
    let text: String
    let canvasSize: CGSize
    let style: MarkerLabelStyle
    let isEditing: Bool
    let onInteractionBegan: () -> Void
    let onChange: (MarkerLabelPlacement) -> Void

    @State private var render: MarkerLabelRender?
    @State private var dragStart: CGPoint?
    @GestureState private var isDragging = false

    private struct Identity: Equatable {
        let text: String
        let size: CGSize
        let style: MarkerLabelStyle
    }

    var body: some View {
        GeometryReader { proxy in
            let canvasFrame = MarkerLabelLayout.aspectFitRect(contentSize: canvasSize,
                in: CGRect(origin: .zero, size: proxy.size))
            let scale = canvasFrame.width / canvasSize.width
            ZStack(alignment: .topLeading) {
                if let render {
                    Image(decorative: render.image, scale: 1)
                        .resizable()
                        .frame(width: render.size.width * scale, height: render.size.height * scale)
                        .overlay {
                            if isEditing {
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(.white, lineWidth: 1.5)
                                    .shadow(color: .black, radius: 1)
                            }
                        }
                        .position(x: canvasFrame.minX + render.frame.midX * scale,
                                  y: canvasFrame.minY + render.frame.midY * scale)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    Color.clear
                        .frame(width: canvasFrame.width, height: canvasFrame.height)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 3)
                            .updating($isDragging) { _, active, _ in active = true }
                            .onChanged { value in
                                guard isEditing else { return }
                                if dragStart == nil {
                                    dragStart = CGPoint(x: render.frame.midX, y: render.frame.midY)
                                    onInteractionBegan()
                                }
                                guard let start = dragStart else { return }
                                move(to: CGPoint(x: start.x + value.translation.width / scale,
                                                 y: start.y + value.translation.height / scale), labelSize: render.size)
                            }
                            .onEnded { _ in dragStart = nil })
                        .position(x: canvasFrame.midX, y: canvasFrame.midY)
                        .allowsHitTesting(isEditing)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("片段序号位置")
                        .accessibilityIdentifier("ClipNumberPosition")
                        .accessibilityValue(String(format: "横向 %.0f%%，纵向 %.0f%%，字号 %.0f%%",
                            style.normalizedCenterX * 100, style.normalizedCenterY * 100, style.fontSizeRatio * 100))
                        .accessibilityHint(isEditing ? "拖动画面移动序号，也可使用方向操作" : "在操作列表中开启序号操作后可调整")
                        .accessibilityAction(named: Text("向左移动序号")) { moveBy(x: -0.05, y: 0) }
                        .accessibilityAction(named: Text("向右移动序号")) { moveBy(x: 0.05, y: 0) }
                        .accessibilityAction(named: Text("向上移动序号")) { moveBy(x: 0, y: -0.05) }
                        .accessibilityAction(named: Text("向下移动序号")) { moveBy(x: 0, y: 0.05) }
                }
            }
        }
        .onChange(of: Identity(text: text, size: canvasSize, style: style), initial: true) { old, new in
            if let existing = render, old.text == new.text, old.size == new.size,
               old.style.fontSizeRatio == new.style.fontSizeRatio,
               old.style.textOpacity == new.style.textOpacity,
               old.style.backgroundOpacity == new.style.backgroundOpacity {
                render = MarkerLabelRendering.layout(image: existing.image, canvasSize: canvasSize, style: style)
            } else {
                render = try? MarkerLabelRendering.make(text: text, canvasSize: canvasSize, style: style)
            }
        }
        .onChange(of: isDragging) { _, active in if !active { dragStart = nil } }
        .onChange(of: isEditing) { _, _ in dragStart = nil }
    }

    private func move(to point: CGPoint, labelSize: CGSize) {
        let center = MarkerLabelLayout.normalizedCenter(forPreviewPoint: point, labelSize: labelSize,
            in: CGRect(origin: .zero, size: canvasSize))
        onChange(MarkerLabelPlacement(fontSizeRatio: style.fontSizeRatio,
            normalizedCenterX: Double(center.x), normalizedCenterY: Double(center.y)).normalized)
    }

    private func moveBy(x: Double, y: Double) {
        guard isEditing, let render else { return }
        onInteractionBegan()
        move(to: CGPoint(x: render.frame.midX + x * canvasSize.width,
                         y: render.frame.midY + y * canvasSize.height), labelSize: render.size)
    }
}
