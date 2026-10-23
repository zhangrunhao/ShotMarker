import AVKit
import SwiftUI
import UIKit

private enum PendingEditorExitAction: Equatable {
    case review
    case videoSelection
    case clip(UUID)
}

struct HighlightClipEditorView: View {
    @ObservedObject var reviewViewModel: HighlightClipReviewViewModel
    @ObservedObject var editorViewModel: HighlightClipEditorViewModel
    @ObservedObject var playbackController: HighlightClipPlaybackController

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var window: HighlightClipTimelineWindow
    @State private var editorErrorMessage: String?
    @State private var playbackLoadAttempt = 0
    @State private var isShowingDiscardConfirmation = false
    @State private var pendingExitAction: PendingEditorExitAction?
    @State private var hasReleasedMedia = false

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
            VStack(spacing: 14) {
                confirmationStatus
                playbackArea(item: item)
                framingControls
                timeReadout(item: item)
                timeline(item: item)
                playbackButton
                relationshipHints
                clipStrip
                errorMessages(itemID: item.id)
            }
            .padding()
        }
        .disabled(isBusy)
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
                .disabled(isBusy)
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
            Text("未确认的范围、取景与保留状态更改不会保存。")
        }
        .onChange(of: playbackController.loadError) { _, error in
            if error == .sourceUnavailable {
                reviewViewModel.markSourceUnavailable(itemID: item.id)
            }
        }
        .onDisappear {
            releaseMedia()
        }
    }

    private var item: HighlightClipReviewItem {
        editorViewModel.workingItem
    }

    private var video: SelectedTrainingVideo {
        editorViewModel.video
    }

    private var context: HighlightClipReviewContext {
        HighlightClipReviewContext(items: reviewViewModel.items, workingItem: item, videos: reviewViewModel.videos)
    }

    private var isBusy: Bool {
        editorViewModel.isSaving || reviewViewModel.isUndoingDecision || reviewViewModel.isSavingDecision
    }

    private var navigationTitle: String {
        "片段 \(context.candidateNumber ?? 1) / \(context.candidateCount)"
    }

    private var confirmationStatus: some View {
        HStack {
            if editorViewModel.hasChanges {
                Label("调整未保存", systemImage: "pencil.circle")
                    .foregroundStyle(.orange)
            } else {
                HighlightClipStateLabel(item: item)
            }
            Spacer()
            if let numbers = item.originalNumberRange {
                Text(numbers.lowerBound == numbers.upperBound
                    ? "打点 \(numbers.lowerBound)"
                    : "打点 \(numbers.lowerBound)–\(numbers.upperBound)")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
    }

    private var confirmationAction: some View {
        VStack(spacing: 8) {
            if let message = editorViewModel.saveErrorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityLabel("保存失败，\(message)")
            }
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 8))
                : AnyLayout(HStackLayout(spacing: 12))
            layout {
                Button {
                    confirmWorkingCopy(isIncluded: false)
                } label: {
                    Label(context.nextItem == nil ? "排除并完成" : "排除并下一段", systemImage: "minus.circle")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("ClipExclude")
                Button {
                    confirmWorkingCopy(isIncluded: true)
                } label: {
                    Label(context.nextItem == nil ? "保留并完成" : "保留并下一段", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(reviewViewModel.unavailableItemIDs.contains(item.id))
                .accessibilityIdentifier("ClipKeep")
            }
            .font(.subheadline.weight(.semibold))
            if editorViewModel.isSaving {
                ProgressView("正在保存…")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .disabled(isBusy)
    }

    private func confirmWorkingCopy(isIncluded: Bool) {
        guard !isBusy else { return }
        playbackController.pause()
        Task { @MainActor in
            guard let navigation = await editorViewModel.confirm(isIncluded: isIncluded) else { return }
            releaseMedia()
            onConfirmationNavigation(navigation)
        }
    }

    private func requestExit(_ action: PendingEditorExitAction) {
        guard !isBusy else {
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
        releaseMedia()
        switch action {
        case let .clip(itemID):
            onConfirmationNavigation(.open(itemID: itemID))
        case .review:
            dismiss()
        case .videoSelection:
            dismiss()
            onRequestVideoReselection()
        }
    }

    private func releaseMedia() {
        guard !hasReleasedMedia else { return }
        hasReleasedMedia = true
        reviewViewModel.cancelFilmstripLoading(itemID: item.id)
        playbackController.reset()
    }

    private func playbackArea(item: HighlightClipReviewItem) -> some View {
        ZStack {
            Color.black
            ClipFramingPlaybackView(player: playbackController.player,
                sourceSize: playbackController.uprightVideoSize,
                framing: editorViewModel.effectiveFraming,
                isEnabled: canAdjustFraming,
                onInteractionBegan: playbackController.pause,
                onChange: editorViewModel.setFraming)

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

    private func playbackErrorOverlay(
        _ error: HighlightClipReviewMediaError,
        item _: HighlightClipReviewItem,
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
                    confirmWorkingCopy(isIncluded: false)
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
        let elapsed = min(max(playbackController.currentTime - item.start, 0), item.duration)
        return Text(String(format: "%.1f / %.1f 秒", elapsed, item.duration))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .accessibilityLabel("片段播放进度")
            .accessibilityValue("\(naturalTime(elapsed))，共 \(naturalTime(item.duration))")
    }

    private func timeline(item: HighlightClipReviewItem) -> some View {
        HighlightClipTimelineView(
            window: window,
            range: item.range,
            playhead: playbackController.currentTime,
            markerReferences: item.markerReferences,
            reviewNumbersByMarkerID: reviewNumbers(for: item),
            frames: filmstripFrames,
            neighbors: context.relationships,
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

    private var canAdjustFraming: Bool {
        playbackController.uprightVideoSize != nil && !playbackController.isLoading
            && playbackController.loadError == nil && !isBusy
    }

    private var framingControls: some View {
        VStack(spacing: 6) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 8))
                : AnyLayout(HStackLayout(spacing: 12))
            layout {
                HStack(spacing: 16) {
                    Button { changeScale(by: -0.1) } label: {
                        Image(systemName: "minus.magnifyingglass").frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("缩小取景")
                    .accessibilityIdentifier("ClipFramingDecrease")
                    .disabled(editorViewModel.effectiveFraming.scale <= 1)
                    Text(String(format: "%.1f×", editorViewModel.effectiveFraming.scale))
                        .font(.body.monospacedDigit())
                        .accessibilityLabel("取景倍率")
                        .accessibilityValue(String(format: "%.1f 倍", editorViewModel.effectiveFraming.scale))
                        .accessibilityIdentifier("ClipFramingScale")
                        .accessibilityAdjustableAction { direction in
                            guard canAdjustFraming else { return }
                            changeScale(by: direction == .increment ? 0.1 : -0.1)
                        }
                    Button { changeScale(by: 0.1) } label: {
                        Image(systemName: "plus.magnifyingglass").frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("放大取景")
                    .accessibilityIdentifier("ClipFramingIncrease")
                    .disabled(editorViewModel.effectiveFraming.scale >= 4)
                }
                Button {
                    playbackController.pause()
                    editorViewModel.restoreOriginalFraming()
                } label: {
                    Text("恢复原画面").frame(minHeight: 44)
                }
                .accessibilityIdentifier("ClipFramingRestore")
                .disabled(editorViewModel.effectiveFraming == .original)
            }
            .disabled(!canAdjustFraming)
        }
    }

    private func changeScale(by delta: Double) {
        guard canAdjustFraming else { return }
        playbackController.pause()
        let current = editorViewModel.effectiveFraming
        let updated = ClipFraming(scale: current.scale + delta,
            centerX: current.centerX, centerY: current.centerY).normalized
        editorViewModel.setFraming(updated)
        if updated == current {
            UIAccessibility.post(notification: .announcement, argument: delta > 0 ? "已到最大倍率 4 倍" : "已到最小倍率 1 倍")
        }
    }

    private var clipStrip: some View {
        HighlightClipNavigationStrip(viewModel: reviewViewModel, currentItemID: item.id, loadsMedia: loadsMedia) { itemID in
            requestExit(.clip(itemID))
        }
    }

    private var relationshipHints: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(context.relationships) { relationship in
                Label(relationshipText(relationship), systemImage: relationship.willMerge ? "arrow.triangle.merge" : "film")
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("ClipRelationships")
    }

    private func relationshipText(_ relationship: HighlightClipNeighborRelationship) -> String {
        let direction = relationship.position == .previous ? "上一段" : "下一段"
        let prefix = "\(direction)（\(relationship.candidateNumber)）"
        let detail = switch relationship.separation {
        case .differentVideo: "来自另一视频"
        case let .overlap(seconds): "重叠 \(shortTime(seconds))"
        case let .gap(seconds): "间隔 \(shortTime(seconds))"
        }
        let effect = relationship.willMerge ? "，生成时合并"
            : (relationship.hasDifferentFraming ? "，取景不同，分别保留"
                : (!relationship.isIncluded ? "，已排除" : ""))
        return "\(prefix)：\(detail)\(effect)"
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
                case let .setStart(start):
                    try editorViewModel.apply(.setStart(start))
                    playbackController.updateRange(item.range)
                    await playbackController.previewStart(of: item.range)
                case let .setEnd(end):
                    try editorViewModel.apply(.setEnd(end))
                    playbackController.updateRange(item.range)
                    await playbackController.previewEnd(of: item.range)
                case let .moveBy(delta):
                    try editorViewModel.apply(.moveBy(delta))
                    playbackController.updateRange(item.range)
                    await playbackController.previewStart(of: item.range)
                case let .preview(time):
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
        Dictionary(uniqueKeysWithValues: item.markerReferences.map { ($0.id, $0.originalMatchedNumber) })
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
