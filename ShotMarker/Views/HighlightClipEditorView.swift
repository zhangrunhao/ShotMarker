import AVKit
import SwiftUI

private enum PendingEditorExitAction: Equatable {
    case review
    case videoSelection
}

struct HighlightClipEditorView: View {
    @ObservedObject var reviewViewModel: HighlightClipReviewViewModel
    @ObservedObject var editorViewModel: HighlightClipEditorViewModel
    @ObservedObject var playbackController: HighlightClipPlaybackController

    @Environment(\.dismiss) private var dismiss
    @State private var window: HighlightClipTimelineWindow
    @State private var editorErrorMessage: String?
    @State private var playbackLoadAttempt = 0
    @State private var isFineTuningExpanded = false
    @State private var isShowingDiscardConfirmation = false
    @State private var pendingExitAction: PendingEditorExitAction?

    private let loadsMedia: Bool
    private let onRequestVideoReselection: () -> Void
    private let onConfirmationNavigation:
        (HighlightClipConfirmationNavigation) -> Void
    private let filmstripCount = 8

    init(
        reviewViewModel: HighlightClipReviewViewModel,
        editorViewModel: HighlightClipEditorViewModel,
        playbackController: HighlightClipPlaybackController,
        loadsMedia: Bool = true,
        onRequestVideoReselection: @escaping () -> Void = {},
        onConfirmationNavigation:
            @escaping (HighlightClipConfirmationNavigation) -> Void = { _ in },
    ) {
        self.reviewViewModel = reviewViewModel
        self.editorViewModel = editorViewModel
        self.playbackController = playbackController
        self.loadsMedia = loadsMedia
        self.onRequestVideoReselection = onRequestVideoReselection
        self.onConfirmationNavigation = onConfirmationNavigation

        _window = State(initialValue: HighlightClipTimelineGeometry.makeWindow(
            range: editorViewModel.workingItem.range,
            videoDuration: editorViewModel.video.duration,
        ))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                confirmationStatus
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
        .disabled(editorViewModel.isSaving)
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
            await reviewViewModel.loadFilmstrip(
                itemID: item.id,
                window: window,
                count: filmstripCount,
                targetSize: .init(width: 180, height: 100),
            )
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("返回") {
                    requestExit(.review)
                }
                .frame(minWidth: 44, minHeight: 44)
                .disabled(editorViewModel.isSaving)
            }
        }
        .safeAreaInset(edge: .bottom) {
            confirmationAction
        }
        .alert("放弃本次调整？", isPresented: $isShowingDiscardConfirmation) {
            Button("继续调整", role: .cancel) {
                pendingExitAction = nil
            }
            Button("放弃", role: .destructive) {
                editorViewModel.discardChanges()
                performPendingExit()
            }
        } message: {
            Text("未确认的范围与保留状态更改不会保存。")
        }
        .onChange(of: playbackController.loadError) { _, error in
            if error == .sourceUnavailable {
                reviewViewModel.markSourceUnavailable(itemID: item.id)
            }
        }
        .onDisappear {
            reviewViewModel.cancelFilmstripLoading(itemID: item.id)
            playbackController.reset()
        }
    }

    private var item: HighlightClipReviewItem {
        editorViewModel.workingItem
    }

    private var video: SelectedTrainingVideo {
        editorViewModel.video
    }

    private var navigationTitle: String {
        return "片段 \(displayNumber(for: item))"
    }

    @ViewBuilder
    private var confirmationStatus: some View {
        HStack {
            switch editorViewModel.displayedConfirmationState {
            case .defaultValue:
                Label("默认", systemImage: "circle.dashed")
                    .foregroundStyle(.orange)
            case .confirmed:
                Label("已确认", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            Spacer()
        }
        .font(.subheadline.weight(.semibold))
        .accessibilityElement(children: .combine)
    }

    private var confirmationAction: some View {
        VStack(spacing: 8) {
            if let message = editorViewModel.saveErrorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityLabel("保存失败，\(message)")
            }
            Button {
                confirmWorkingCopy()
            } label: {
                HStack {
                    if editorViewModel.isSaving {
                        ProgressView()
                    }
                    Text(confirmButtonTitle)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(editorViewModel.isSaving || cannotConfirmIncludedUnavailableSource)
        }
        .padding()
        .background(.regularMaterial)
    }

    private var cannotConfirmIncludedUnavailableSource: Bool {
        editorViewModel.workingItem.isIncluded
            && reviewViewModel.unavailableItemIDs.contains(editorViewModel.workingItem.id)
    }

    private var confirmButtonTitle: String {
        if editorViewModel.isSaving {
            return "正在保存…"
        }
        return editorViewModel.workingItem.isIncluded
            ? "确认片段"
            : "排除并确认片段"
    }

    private func confirmWorkingCopy() {
        playbackController.pause()
        Task { @MainActor in
            guard let navigation = await editorViewModel.confirm() else {
                return
            }
            onConfirmationNavigation(navigation)
        }
    }

    private func requestExit(_ action: PendingEditorExitAction) {
        guard !editorViewModel.isSaving else {
            return
        }
        guard editorViewModel.hasChanges else {
            performExit(action)
            return
        }
        pendingExitAction = action
        isShowingDiscardConfirmation = true
    }

    private func performPendingExit() {
        guard let action = pendingExitAction else { return }
        pendingExitAction = nil
        performExit(action)
    }

    private func performExit(_ action: PendingEditorExitAction) {
        reviewViewModel.cancelFilmstripLoading(itemID: editorViewModel.workingItem.id)
        playbackController.reset()
        dismiss()
        if action == .videoSelection {
            onRequestVideoReselection()
        }
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
                Button("排除并确认片段") {
                    editorViewModel.setIncluded(false)
                    confirmWorkingCopy()
                }
                .buttonStyle(.borderedProminent)

                Button("返回重新选择视频") {
                    requestExit(.videoSelection)
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
        DisclosureGroup(
            "精确范围调整",
            isExpanded: $isFineTuningExpanded,
        ) {
            VStack(alignment: .leading, spacing: 14) {
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
            .padding(.top, 10)
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityValue(isFineTuningExpanded ? "已展开" : "已收起")
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
                    set: { editorViewModel.setIncluded($0) },
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
        if let itemError = reviewViewModel.itemErrorMessages[itemID] {
            Text(itemError)
                .font(.footnote)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var filmstripFrames: [Data?] {
        guard reviewViewModel.filmstripWindowsByItemID[item.id] == window,
              let frames = reviewViewModel.filmstripFramesByItemID[item.id]
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
            reviewViewModel.markSourceUnavailable(itemID: item.id)
        }
    }

    private func performTimelineAction(_ action: HighlightClipTimelineAction) {
        Task { @MainActor in
            do {
                switch action {
                case .setStart(let start):
                    try editorViewModel.apply(.setStart(start))
                    playbackController.updateRange(item.range)
                    await playbackController.previewStart(of: item.range)
                case .setEnd(let end):
                    try editorViewModel.apply(.setEnd(end))
                    playbackController.updateRange(item.range)
                    await playbackController.previewEnd(of: item.range)
                case .moveBy(let delta):
                    try editorViewModel.apply(.moveBy(delta))
                    playbackController.updateRange(item.range)
                    await playbackController.previewStart(of: item.range)
                case .preview(let time):
                    let previewTime = min(max(time, 0), video.duration)
                    await playbackController.preview(at: previewTime)
                }
                editorErrorMessage = nil
                shiftWindowToCurrentRange()
            } catch {
                editorErrorMessage = userFacingMessage(for: error)
            }
        }
    }

    private func restoreDefaultRange() {
        editorViewModel.restoreDefault()
        playbackController.updateRange(item.range)
        Task { @MainActor in
            await playbackController.previewStart(of: item.range)
        }
        editorErrorMessage = nil
        shiftWindowToCurrentRange()
    }

    private func shiftWindowToCurrentRange() {
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
        let numberRange = reviewViewModel.summary.displayNumberRangesByItemID[item.id]
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
        let range = reviewViewModel.summary.displayNumberRangesByItemID[item.id]
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
        let reviewViewModel = HighlightClipReviewPreviewFixtures.editorReviewViewModel()
        let editorViewModel = HighlightClipReviewPreviewFixtures.editorViewModel(
            reviewViewModel: reviewViewModel,
        )
        NavigationStack {
            HighlightClipEditorView(
                reviewViewModel: reviewViewModel,
                editorViewModel: editorViewModel,
                playbackController: HighlightClipReviewPreviewFixtures.playbackController(),
                loadsMedia: false,
            )
        }
    }
#endif
