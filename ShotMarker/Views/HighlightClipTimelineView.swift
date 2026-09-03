import SwiftUI
import UIKit

struct HighlightClipTimelineView: View {
    let window: HighlightClipTimelineWindow
    let range: HighlightClipRange
    let playhead: TimeInterval
    let markerReferences: [HighlightClipMarkerReference]
    let reviewNumbersByMarkerID: [UUID: Int]
    let frames: [Data?]
    let onAction: (HighlightClipTimelineAction) -> Void

    @GestureState private var startGestureRange: HighlightClipRange?
    @GestureState private var endGestureRange: HighlightClipRange?
    @GestureState private var playheadGestureTime: TimeInterval?
    @State private var moveDragState = HighlightClipTimelineDragState()

    var body: some View {
        GeometryReader { proxy in
            let width = max(Double(proxy.size.width), 0)
            let height = max(proxy.size.height, 132)
            let startX = HighlightClipTimelineGeometry.x(
                for: range.start,
                window: window,
                width: width,
            )
            let endX = HighlightClipTimelineGeometry.x(
                for: range.end,
                window: window,
                width: width,
            )
            let playheadX = HighlightClipTimelineGeometry.x(
                for: playhead,
                window: window,
                width: width,
            )
            let handleHitXs = handleHitRegionXs(
                startX: startX,
                endX: endX,
                width: width,
            )

            ZStack(alignment: .topLeading) {
                frameStrip
                selectionOverlay(
                    startX: startX,
                    endX: endX,
                    height: height,
                )
                markerLines(width: width, height: height)
                staticControlLines(
                    startX: startX,
                    endX: endX,
                    playheadX: playheadX,
                    height: height,
                )
                startHandle(x: handleHitXs.start, width: width, height: height)
                endHandle(x: handleHitXs.end, width: width, height: height)
                moveGrip(startX: startX, endX: endX, width: width, height: height)
                playheadHandle(x: playheadX, width: width)
            }
            .frame(width: proxy.size.width, height: height)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .frame(height: 144)
    }

    @ViewBuilder
    private var frameStrip: some View {
        HStack(spacing: 0) {
            if frames.isEmpty {
                framePlaceholder
            } else {
                ForEach(Array(frames.enumerated()), id: \.offset) { _, data in
                    frameCell(data: data)
                }
            }
        }
    }

    @ViewBuilder
    private func frameCell(data: Data?) -> some View {
        if let data, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
        } else {
            framePlaceholder
        }
    }

    private var framePlaceholder: some View {
        Color(uiColor: .secondarySystemFill)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                Image(systemName: "film")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
    }

    private func selectionOverlay(
        startX: Double,
        endX: Double,
        height: CGFloat,
    ) -> some View {
        let selectionWidth = max(endX - startX, 1)
        return Rectangle()
            .fill(Color.accentColor.opacity(0.2))
            .overlay {
                Rectangle()
                    .stroke(Color.accentColor, lineWidth: 2)
            }
            .frame(width: selectionWidth, height: height)
            .position(x: startX + selectionWidth / 2, y: height / 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func markerLines(width: Double, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(visibleMarkerReferences) { reference in
                let markerX = HighlightClipTimelineGeometry.x(
                    for: reference.timeInVideo,
                    window: window,
                    width: width,
                )
                let reviewNumber = reviewNumbersByMarkerID[reference.id]
                    ?? reference.originalMatchedNumber

                VStack(spacing: 2) {
                    Text("\(reviewNumber)")
                        .font(.caption2.monospacedDigit().bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.75), in: Capsule())
                    Rectangle()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 1)
                }
                .frame(width: 36, height: height - 4)
                .position(x: markerX, y: height / 2)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("打点 \(reviewNumber)")
                .accessibilityValue(timeDescription(reference.timeInVideo))
            }
        }
        .allowsHitTesting(false)
    }

    private func staticControlLines(
        startX: Double,
        endX: Double,
        playheadX: Double,
        height: CGFloat,
    ) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 4, height: height)
                .position(x: startX, y: height / 2)
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 4, height: height)
                .position(x: endX, y: height / 2)
            Rectangle()
                .fill(Color.orange)
                .frame(width: 2, height: height)
                .position(x: playheadX, y: height / 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func startHandle(x: Double, width: Double, height: CGFloat) -> some View {
        timelineHandle(symbol: "chevron.right")
            .contentShape(Rectangle())
            .highPriorityGesture(startGesture(width: width))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("片段起点")
            .accessibilityValue(timeDescription(range.start))
            .accessibilityAdjustableAction { direction in
                guard let delta = adjustmentDelta(for: direction) else {
                    return
                }
                onAction(.setStart(range.start + delta))
            }
            .position(x: hitRegionX(x, width: width), y: height / 2)
    }

    private func endHandle(x: Double, width: Double, height: CGFloat) -> some View {
        timelineHandle(symbol: "chevron.left")
            .contentShape(Rectangle())
            .highPriorityGesture(endGesture(width: width))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("片段终点")
            .accessibilityValue(timeDescription(range.end))
            .accessibilityAdjustableAction { direction in
                guard let delta = adjustmentDelta(for: direction) else {
                    return
                }
                onAction(.setEnd(range.end + delta))
            }
            .position(x: hitRegionX(x, width: width), y: height / 2)
    }

    private func moveGrip(
        startX: Double,
        endX: Double,
        width: Double,
        height: CGFloat,
    ) -> some View {
        let centerX = hitRegionX((startX + endX) / 2, width: width)
        return ZStack {
            Color.clear
            Image(systemName: "line.3.horizontal")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.black.opacity(0.72), in: Capsule())
        }
        .frame(width: 52, height: 44)
        .contentShape(Rectangle())
        .highPriorityGesture(moveGesture(width: width))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("移动整个片段")
        .accessibilityValue(
            "起点 \(timeDescription(range.start))，终点 \(timeDescription(range.end))",
        )
        .accessibilityAdjustableAction { direction in
            guard let delta = adjustmentDelta(for: direction) else {
                return
            }
            onAction(.moveBy(delta))
        }
        .position(x: centerX, y: height - 22)
    }

    private func playheadHandle(x: Double, width: Double) -> some View {
        ZStack {
            Color.clear
            Circle()
                .fill(Color.orange)
                .frame(width: 18, height: 18)
                .overlay {
                    Circle().stroke(Color.white, lineWidth: 2)
                }
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .highPriorityGesture(playheadGesture(width: width))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("预览位置")
        .accessibilityValue(timeDescription(playhead))
        .accessibilityAdjustableAction { direction in
            guard let delta = adjustmentDelta(for: direction) else {
                return
            }
            let time = min(max(playhead + delta, window.start), window.end)
            onAction(.preview(time))
        }
        .position(x: hitRegionX(x, width: width), y: 22)
    }

    private func timelineHandle(symbol: String) -> some View {
        ZStack {
            Color.clear
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor)
                .frame(width: 24, height: 36)
                .overlay {
                    Image(systemName: symbol)
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                }
        }
        .frame(width: 44, height: 44)
    }

    private func startGesture(width: Double) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .updating($startGestureRange) { _, initialRange, _ in
                if initialRange == nil {
                    initialRange = range
                }
            }
            .onChanged { value in
                onAction(HighlightClipTimelineGeometry.action(
                    for: .startHandle,
                    translationX: Double(value.translation.width),
                    range: startGestureRange ?? range,
                    playhead: playhead,
                    window: window,
                    width: width,
                ))
            }
    }

    private func endGesture(width: Double) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .updating($endGestureRange) { _, initialRange, _ in
                if initialRange == nil {
                    initialRange = range
                }
            }
            .onChanged { value in
                onAction(HighlightClipTimelineGeometry.action(
                    for: .endHandle,
                    translationX: Double(value.translation.width),
                    range: endGestureRange ?? range,
                    playhead: playhead,
                    window: window,
                    width: width,
                ))
            }
    }

    private func moveGesture(width: Double) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                let incrementalTranslation = moveDragState.incrementalTranslation(
                    for: Double(value.translation.width),
                )
                onAction(HighlightClipTimelineGeometry.action(
                    for: .moveRange,
                    translationX: incrementalTranslation,
                    range: range,
                    playhead: playhead,
                    window: window,
                    width: width,
                ))
            }
            .onEnded { _ in
                moveDragState.reset()
            }
    }

    private func playheadGesture(width: Double) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .updating($playheadGestureTime) { _, initialTime, _ in
                if initialTime == nil {
                    initialTime = playhead
                }
            }
            .onChanged { value in
                onAction(HighlightClipTimelineGeometry.action(
                    for: .playhead,
                    translationX: Double(value.translation.width),
                    range: range,
                    playhead: playheadGestureTime ?? playhead,
                    window: window,
                    width: width,
                ))
            }
    }

    private var visibleMarkerReferences: [HighlightClipMarkerReference] {
        markerReferences.filter {
            $0.timeInVideo >= window.start && $0.timeInVideo <= window.end
        }
    }

    private func hitRegionX(_ x: Double, width: Double) -> Double {
        guard width.isFinite, width >= 44 else {
            return max(width / 2, 0)
        }
        return min(max(x, 22), width - 22)
    }

    private func handleHitRegionXs(
        startX: Double,
        endX: Double,
        width: Double,
    ) -> (start: Double, end: Double) {
        var start = hitRegionX(startX, width: width)
        var end = hitRegionX(endX, width: width)
        guard width >= 88, end - start < 44 else {
            return (start, end)
        }

        let center = (start + end) / 2
        start = center - 22
        end = center + 22
        if start < 22 {
            end += 22 - start
            start = 22
        }
        if end > width - 22 {
            start -= end - (width - 22)
            end = width - 22
        }
        return (start, end)
    }

    private func adjustmentDelta(
        for direction: AccessibilityAdjustmentDirection,
    ) -> TimeInterval? {
        switch direction {
        case .increment:
            0.5
        case .decrement:
            -0.5
        @unknown default:
            nil
        }
    }

    private func timeDescription(_ time: TimeInterval) -> String {
        guard time.isFinite else {
            return "时间不可用"
        }

        let clampedTime = max(time, 0)
        let minutes = Int(clampedTime) / 60
        let seconds = clampedTime - TimeInterval(minutes * 60)
        let secondsText = seconds.formatted(
            .number.precision(.fractionLength(1)),
        )
        if minutes > 0 {
            return "\(minutes) 分 \(secondsText) 秒"
        }
        return "\(secondsText) 秒"
    }
}
