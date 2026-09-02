#if os(iOS)
    import SwiftUI
    import UIKit

    struct MarkerLabelSettingsView: View {
        let thumbnailData: Data?
        let previewLabel: String
        let isDisabled: Bool
        @Binding var style: MarkerLabelStyle

        @State private var labelSize: CGSize = .zero

        private var previewImage: UIImage? {
            thumbnailData.flatMap(UIImage.init(data:))
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                GeometryReader { proxy in
                    let previewBounds = CGRect(origin: .zero, size: proxy.size)
                    let videoFrame = if let previewImage {
                        MarkerLabelLayout.aspectFitRect(
                            contentSize: previewImage.size,
                            in: previewBounds,
                        )
                    } else {
                        previewBounds
                    }
                    let normalized = style.normalized
                    let fontSize = min(videoFrame.width, videoFrame.height)
                        * CGFloat(normalized.fontSizeRatio)

                    ZStack(alignment: .topLeading) {
                        Color.black

                        if let previewImage {
                            Image(uiImage: previewImage)
                                .resizable()
                                .scaledToFit()
                                .frame(
                                    width: previewBounds.width,
                                    height: previewBounds.height,
                                )
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "video.slash")
                                Text("暂时无法显示视频预览")
                                    .font(.footnote)
                            }
                            .foregroundStyle(.secondary)
                            .frame(
                                width: previewBounds.width,
                                height: previewBounds.height,
                            )
                            .background(Color.secondary.opacity(0.18))
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("暂时无法显示视频预览")
                        }

                        markerLabel(fontSize: fontSize, videoFrame: videoFrame)
                            .position(
                                MarkerLabelLayout.previewCenter(
                                    for: CGPoint(
                                        x: CGFloat(normalized.normalizedCenterX),
                                        y: CGFloat(normalized.normalizedCenterY),
                                    ),
                                    labelSize: labelSize,
                                    in: videoFrame,
                                ),
                            )
                    }
                    .coordinateSpace(name: MarkerLabelPreviewCoordinateSpace.name)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .onPreferenceChange(MarkerLabelSizePreferenceKey.self) { size in
                        labelSize = size
                    }
                }
                .aspectRatio(16.0 / 9.0, contentMode: .fit)

                sliderRow(
                    title: "文字大小",
                    keyPath: \.fontSizeRatio,
                    range: MarkerLabelStyle.fontSizeRatioRange,
                    step: 0.01,
                    hint: "相对于完整视频画面短边，范围 4% 到 16%",
                )
                sliderRow(
                    title: "文字不透明度",
                    keyPath: \.textOpacity,
                    range: MarkerLabelStyle.opacityRange,
                    step: 0.05,
                    hint: "0% 完全透明，100% 完全不透明",
                )
                sliderRow(
                    title: "黑底不透明度",
                    keyPath: \.backgroundOpacity,
                    range: MarkerLabelStyle.opacityRange,
                    step: 0.05,
                    hint: "0% 完全透明，100% 完全不透明",
                )
            }
            .disabled(isDisabled)
        }

        private func markerLabel(fontSize: CGFloat, videoFrame: CGRect) -> some View {
            let normalized = style.normalized
            return Text(previewLabel)
                .font(.system(size: fontSize, weight: .black))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(normalized.textOpacity))
                .padding(.horizontal, fontSize * 0.55)
                .padding(.vertical, fontSize * 0.28)
                .background(
                    Color.black.opacity(normalized.backgroundOpacity),
                    in: RoundedRectangle(cornerRadius: fontSize * 0.25),
                )
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: MarkerLabelSizePreferenceKey.self,
                            value: proxy.size,
                        )
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(
                        minimumDistance: 0,
                        coordinateSpace: .named(MarkerLabelPreviewCoordinateSpace.name),
                    )
                    .onChanged { value in
                        updateStyle(for: value.location, in: videoFrame)
                    },
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("片段序数位置")
                .accessibilityValue(
                    "横向 \(percentage(normalized.normalizedCenterX))%，纵向 \(percentage(normalized.normalizedCenterY))%",
                )
                .accessibilityHint("调整所有片段共用的序数位置")
                .accessibilityAction(named: Text("向左移动")) {
                    moveBy(x: -0.05, y: 0, in: videoFrame)
                }
                .accessibilityAction(named: Text("向右移动")) {
                    moveBy(x: 0.05, y: 0, in: videoFrame)
                }
                .accessibilityAction(named: Text("向上移动")) {
                    moveBy(x: 0, y: -0.05, in: videoFrame)
                }
                .accessibilityAction(named: Text("向下移动")) {
                    moveBy(x: 0, y: 0.05, in: videoFrame)
                }
        }

        private func updateStyle(for location: CGPoint, in videoFrame: CGRect) {
            let center = MarkerLabelLayout.normalizedCenter(
                forPreviewPoint: location,
                labelSize: labelSize,
                in: videoFrame,
            )
            var updated = style
            updated.normalizedCenterX = Double(center.x)
            updated.normalizedCenterY = Double(center.y)
            style = updated.normalized
        }

        private func moveBy(x deltaX: Double, y deltaY: Double, in videoFrame: CGRect) {
            let normalized = style.normalized
            let requestedPoint = CGPoint(
                x: videoFrame.minX
                    + CGFloat(normalized.normalizedCenterX + deltaX) * videoFrame.width,
                y: videoFrame.minY
                    + CGFloat(normalized.normalizedCenterY + deltaY) * videoFrame.height,
            )
            updateStyle(for: requestedPoint, in: videoFrame)
        }

        private func sliderRow(
            title: String,
            keyPath: WritableKeyPath<MarkerLabelStyle, Double>,
            range: ClosedRange<Double>,
            step: Double,
            hint: String,
        ) -> some View {
            let value = style[keyPath: keyPath]
            return VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title)
                    Spacer()
                    Text("\(percentage(value))%")
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: styleBinding(keyPath),
                    in: range,
                    step: step,
                )
                .accessibilityLabel(title)
                .accessibilityValue("\(percentage(value))%")
                .accessibilityHint(hint)
            }
        }

        private func styleBinding(
            _ keyPath: WritableKeyPath<MarkerLabelStyle, Double>,
        ) -> Binding<Double> {
            Binding(
                get: { style[keyPath: keyPath] },
                set: { value in
                    var updated = style
                    updated[keyPath: keyPath] = value
                    style = updated.normalized
                },
            )
        }

        private func percentage(_ value: Double) -> Int {
            Int((value * 100).rounded())
        }
    }

    private enum MarkerLabelPreviewCoordinateSpace {
        static let name = "MarkerLabelPreview"
    }

    private struct MarkerLabelSizePreferenceKey: PreferenceKey {
        static let defaultValue = CGSize.zero

        static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
            value = nextValue()
        }
    }
#endif
