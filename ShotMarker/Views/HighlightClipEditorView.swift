import AVKit
import SwiftUI

struct HighlightClipEditorView: View {
    @ObservedObject var viewModel: HighlightClipReviewViewModel
    let itemID: UUID
    @ObservedObject var playbackController: HighlightClipPlaybackController

    @Environment(\.dismiss) private var dismiss
    @State private var window: HighlightClipTimelineWindow
    @State private var editorErrorMessage: String?
    @State private var playbackLoadAttempt = 0

    private let loadsMedia: Bool
    private let filmstripCount = 8

    init(
        viewModel: HighlightClipReviewViewModel,
        itemID: UUID,
        playbackController: HighlightClipPlaybackController,
        loadsMedia: Bool = true,
    ) {
        self.viewModel = viewModel
        self.itemID = itemID
        self.playbackController = playbackController
        self.loadsMedia = loadsMedia

        let item = viewModel.items.first { $0.id == itemID }
        let video = item.flatMap { item in
            viewModel.videos.first { $0.id == item.videoID }
        }
        _window = State(initialValue: HighlightClipTimelineGeometry.makeWindow(
            range: item?.range ?? .init(start: 0, duration: 0),
            videoDuration: video?.duration ?? 0,
        ))
    }

    var body: some View {
        Group {
            if let item, let video {
                ScrollView {
                    VStack(spacing: 18) {
                        playbackArea(item: item)
                        timeReadout(item: item)
                        timeline(item: item)
                        playbackButton
                        fineTuneControls(item: item, video: video)
                        inclusionAndRestore(item: item)
                        errorMessages(itemID: item.id)
                    }
                    .padding()
                }
                .task(id: playbackLoadAttempt) {
                    guard loadsMedia else {
                        return
                    }
                    await loadPlayback(video: video, range: item.range)
                }
                .task(id: window) {
                    guard loadsMedia else {
                        return
                    }
                    await viewModel.loadFilmstrip(
                        itemID: item.id,
                        window: window,
                        count: filmstripCount,
                        targetSize: .init(width: 180, height: 100),
                    )
                }
            } else {
                ContentUnavailableView(
                    "片段不可用",
                    systemImage: "film",
                    description: Text("找不到此片段或来源视频。"),
                )
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: playbackController.loadError) { _, error in
            if error == .sourceUnavailable {
                viewModel.markSourceUnavailable(itemID: itemID)
            }
        }
        .onDisappear {
            viewModel.cancelFilmstripLoading(itemID: itemID)
            playbackController.reset()
        }
    }

    private var item: HighlightClipReviewItem? {
        viewModel.items.first { $0.id == itemID }
    }

    private var video: SelectedTrainingVideo? {
        guard let item else {
            return nil
        }
        return viewModel.videos.first { $0.id == item.videoID }
    }

    private var navigationTitle: String {
        guard let item else {
            return "片段"
        }
        return "片段 \(displayNumber(for: item))"
    }

    private func playbackArea(item: HighlightClipReviewItem) -> some View {
        ZStack {
            Color.black
            VideoPlayer(player: playbackController.player)
                .disabled(true)

            if playbackController.isLoading {
                ProgressView("正在载入视频…")
                    .tint(.white)
                    .foregroundStyle(.white)
                    .padding()
                    .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 10))
            } else if let loadError = playbackController.loadError {
                playbackErrorOverlay(loadError, item: item)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("片段播放预览")
    }

    @ViewBuilder
    private func playbackErrorOverlay(
        _ error: HighlightClipReviewMediaError,
        item: HighlightClipReviewItem,
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(playbackController.errorMessage ?? "暂时无法载入视频。")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)

            if error == .sourceUnavailable {
                Button("排除此片段") {
                    viewModel.setIncluded(false, itemID: item.id)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)

                Button("返回重新选择视频") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .tint(.white)
            } else {
                Button("重试") {
                    playbackLoadAttempt += 1
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.78))
    }

    private func timeReadout(item: HighlightClipReviewItem) -> some View {
        Grid(horizontalSpacing: 18, verticalSpacing: 8) {
            GridRow {
                timeValue(title: "当前位置", value: playbackController.currentTime)
                timeValue(title: "起点", value: item.start)
            }
            GridRow {
                timeValue(title: "终点", value: item.range.end)
                timeValue(title: "时长", value: item.duration)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func timeValue(title: String, value: TimeInterval) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(shortTime(value))
                .font(.body.monospacedDigit().weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(naturalTime(value))
    }

    private func timeline(item: HighlightClipReviewItem) -> some View {
        HighlightClipTimelineView(
            window: window,
            range: item.range,
            playhead: playbackController.currentTime,
            markerReferences: item.markerReferences,
            reviewNumbersByMarkerID: reviewNumbers(for: item),
            frames: filmstripFrames,
        ) { action in
            performTimelineAction(action)
        }
    }

    private var playbackButton: some View {
        Button {
            if playbackController.isPlaying {
                playbackController.pause()
            } else {
                playbackController.play()
            }
        } label: {
            Label(
                playbackController.isPlaying ? "暂停" : "播放片段",
                systemImage: playbackController.isPlaying ? "pause.fill" : "play.fill",
            )
            .frame(minWidth: 132, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .disabled(playbackController.isLoading || playbackController.loadError != nil)
    }

    private func fineTuneControls(
        item: HighlightClipReviewItem,
        video: SelectedTrainingVideo,
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("精调范围")
                .font(.headline)

            fineTuneGroup(
                title: "起点",
                negativeLabel: "-0.5s 更早",
                positiveLabel: "+0.5s 更晚",
                negativeDisabled: item.start <= 0,
                positiveDisabled: item.duration <= 1,
                negativeDisabledReason: "已到达视频起点",
                positiveDisabledReason: "片段已达到最短时长",
                negativeAction: .setStart(item.start - 0.5),
                positiveAction: .setStart(item.start + 0.5),
            )
            fineTuneGroup(
                title: "终点",
                negativeLabel: "-0.5s 更早",
                positiveLabel: "+0.5s 更晚",
                negativeDisabled: item.duration <= 1,
                positiveDisabled: item.range.end >= video.duration,
                negativeDisabledReason: "片段已达到最短时长",
                positiveDisabledReason: "已到达视频终点",
                negativeAction: .setEnd(item.range.end - 0.5),
                positiveAction: .setEnd(item.range.end + 0.5),
            )
            fineTuneGroup(
                title: "整体",
                negativeLabel: "-0.5s 向前",
                positiveLabel: "+0.5s 向后",
                negativeDisabled: item.start <= 0,
                positiveDisabled: item.range.end >= video.duration,
                negativeDisabledReason: "已到达视频起点",
                positiveDisabledReason: "已到达视频终点",
                negativeAction: .moveBy(-0.5),
                positiveAction: .moveBy(0.5),
            )
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func fineTuneGroup(
        title: String,
        negativeLabel: String,
        positiveLabel: String,
        negativeDisabled: Bool,
        positiveDisabled: Bool,
        negativeDisabledReason: String,
        positiveDisabledReason: String,
        negativeAction: HighlightClipTimelineAction,
        positiveAction: HighlightClipTimelineAction,
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            HStack {
                fineTuneButton(
                    negativeLabel,
                    disabled: negativeDisabled,
                    disabledReason: negativeDisabledReason,
                    action: negativeAction,
                )
                fineTuneButton(
                    positiveLabel,
                    disabled: positiveDisabled,
                    disabledReason: positiveDisabledReason,
                    action: positiveAction,
                )
            }
        }
    }

    private func fineTuneButton(
        _ title: String,
        disabled: Bool,
        disabledReason: String,
        action: HighlightClipTimelineAction,
    ) -> some View {
        Button(title) {
            performTimelineAction(action)
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity, minHeight: 44)
        .disabled(disabled)
        .accessibilityHint(disabled ? disabledReason : "调整后立即预览")
    }

    private func inclusionAndRestore(item: HighlightClipReviewItem) -> some View {
        VStack(spacing: 10) {
            Toggle(
                "保留此片段",
                isOn: Binding(
                    get: { item.isIncluded },
                    set: { viewModel.setIncluded($0, itemID: item.id) },
                ),
            )
            .frame(minHeight: 44)

            Button("恢复默认范围") {
                restoreDefaultRange()
            }
            .frame(minHeight: 44)
            .disabled(item.range == item.defaultRange)
        }
    }

    @ViewBuilder
    private func errorMessages(itemID: UUID) -> some View {
        if let editorErrorMessage {
            Text(editorErrorMessage)
                .font(.footnote)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("范围调整失败，\(editorErrorMessage)")
        }
        if let itemError = viewModel.itemErrorMessages[itemID] {
            Text(itemError)
                .font(.footnote)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var filmstripFrames: [Data?] {
        guard viewModel.filmstripWindowsByItemID[itemID] == window,
              let frames = viewModel.filmstripFramesByItemID[itemID]
        else {
            return Array(repeating: nil, count: filmstripCount)
        }
        return frames
    }

    private func loadPlayback(
        video: SelectedTrainingVideo,
        range: HighlightClipRange,
    ) async {
        await playbackController.load(video: video, range: range)
        if playbackController.loadError == .sourceUnavailable {
            viewModel.markSourceUnavailable(itemID: itemID)
        }
    }

    private func performTimelineAction(_ action: HighlightClipTimelineAction) {
        Task { @MainActor in
            do {
                try await viewModel.handleTimelineAction(
                    action,
                    itemID: itemID,
                    playbackController: playbackController,
                )
                editorErrorMessage = nil
                shiftWindowToCurrentRange()
            } catch {
                editorErrorMessage = userFacingMessage(for: error)
            }
        }
    }

    private func restoreDefaultRange() {
        viewModel.restoreDefault(itemID: itemID)
        guard let item else {
            return
        }
        playbackController.updateRange(item.range)
        Task { @MainActor in
            await playbackController.previewStart(of: item.range)
        }
        editorErrorMessage = nil
        shiftWindowToCurrentRange()
    }

    private func shiftWindowToCurrentRange() {
        guard let item,
              let video = viewModel.videos.first(where: { $0.id == item.videoID })
        else {
            return
        }
        let shiftedWindow = HighlightClipTimelineGeometry.shiftedWindow(
            window,
            toContain: item.range,
            videoDuration: video.duration,
        )
        if shiftedWindow != window {
            window = shiftedWindow
        }
    }

    private func reviewNumbers(for item: HighlightClipReviewItem) -> [UUID: Int] {
        let numberRange = viewModel.summary.displayNumberRangesByItemID[item.id]
            ?? item.originalNumberRange
        guard let lowerBound = numberRange?.lowerBound else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: item.markerReferences.enumerated().map {
            (index, reference) in
            (reference.id, lowerBound + index)
        })
    }

    private func displayNumber(for item: HighlightClipReviewItem) -> String {
        let range = viewModel.summary.displayNumberRangesByItemID[item.id]
            ?? item.originalNumberRange
        guard let range else {
            return "—"
        }
        return range.lowerBound == range.upperBound
            ? "\(range.lowerBound)"
            : "\(range.lowerBound)–\(range.upperBound)"
    }

    private func shortTime(_ time: TimeInterval) -> String {
        guard time.isFinite else {
            return "—"
        }
        return String(format: "%.1fs", max(time, 0))
    }

    private func naturalTime(_ time: TimeInterval) -> String {
        guard time.isFinite else {
            return "时间不可用"
        }
        let clampedTime = max(time, 0)
        let minutes = Int(clampedTime) / 60
        let seconds = clampedTime - TimeInterval(minutes * 60)
        let secondsText = seconds.formatted(.number.precision(.fractionLength(1)))
        return minutes > 0
            ? "\(minutes) 分 \(secondsText) 秒"
            : "\(secondsText) 秒"
    }

    private func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription
        {
            return description
        }
        return error.localizedDescription
    }
}

#if DEBUG
    #Preview("合并片段编辑") {
        let viewModel = HighlightClipReviewPreviewFixtures.editorViewModel()
        NavigationStack {
            HighlightClipEditorView(
                viewModel: viewModel,
                itemID: viewModel.items.last!.id,
                playbackController: HighlightClipReviewPreviewFixtures.playbackController(),
                loadsMedia: false,
            )
        }
    }
#endif
