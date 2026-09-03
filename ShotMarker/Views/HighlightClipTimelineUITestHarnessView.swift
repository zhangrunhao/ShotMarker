#if DEBUG
    import SwiftUI

    struct HighlightClipTimelineUITestHarnessView: View {
        @State private var range = HighlightClipRange(start: 5, duration: 4)
        @State private var playhead: TimeInterval = 2

        private let window = HighlightClipTimelineWindow(start: 0, duration: 20)

        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 18) {
                        valueReadout("起点", value: range.start, identifier: "TimelineStartValue")
                        valueReadout("终点", value: range.end, identifier: "TimelineEndValue")
                        valueReadout("时长", value: range.duration, identifier: "TimelineDurationValue")
                        valueReadout("当前位置", value: playhead, identifier: "TimelinePlayheadValue")

                        HighlightClipTimelineView(
                            window: window,
                            range: range,
                            playhead: playhead,
                            markerReferences: [],
                            reviewNumbersByMarkerID: [:],
                            frames: [],
                            onAction: apply,
                        )

                        Color.clear.frame(height: 320)
                    }
                    .padding()
                }
                .navigationTitle("时间轴拖动测试")
            }
        }

        private func valueReadout(
            _ title: String,
            value: TimeInterval,
            identifier: String,
        ) -> some View {
            Text("\(title) \(value.formatted(.number.precision(.fractionLength(3))))")
                .monospacedDigit()
                .accessibilityIdentifier(identifier)
        }

        private func apply(_ action: HighlightClipTimelineAction) {
            switch action {
            case .setStart(let start):
                let end = range.end
                let clampedStart = min(max(start, window.start), end - 1)
                range = HighlightClipRange(start: clampedStart, duration: end - clampedStart)
            case .setEnd(let end):
                let clampedEnd = min(max(end, range.start + 1), window.end)
                range = HighlightClipRange(start: range.start, duration: clampedEnd - range.start)
            case .moveBy(let delta):
                let maximumStart = window.end - range.duration
                range = HighlightClipRange(
                    start: min(max(range.start + delta, window.start), maximumStart),
                    duration: range.duration,
                )
            case .preview(let time):
                playhead = min(max(time, window.start), window.end)
            }
        }
    }
#endif
