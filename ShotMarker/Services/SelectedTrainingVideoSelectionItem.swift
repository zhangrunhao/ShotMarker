import Foundation

enum SelectedTrainingVideoUnavailableReason: Equatable {
    case failedToLoad
    case missingRecordedStartAt
    case invalidDuration
    case notReady
    case noMarkerCoverage
    case photoLibraryAccessDenied

    var displayText: String {
        switch self {
        case .failedToLoad:
            "读取失败"
        case .missingRecordedStartAt:
            "缺少拍摄时间"
        case .invalidDuration:
            "视频时长无效"
        case .notReady:
            "未下载或未准备好"
        case .noMarkerCoverage:
            "不覆盖本次训练"
        case .photoLibraryAccessDenied:
            "没有相册权限"
        }
    }

    var logReason: String {
        switch self {
        case .failedToLoad:
            "failedToLoad"
        case .missingRecordedStartAt:
            "missingRecordedStartAt"
        case .invalidDuration:
            "invalidDuration"
        case .notReady:
            "notReady"
        case .noMarkerCoverage:
            "noMarkerCoverage"
        case .photoLibraryAccessDenied:
            "photoLibraryAccessDenied"
        }
    }
}

struct SelectedTrainingVideoSelectionItem: Identifiable, Equatable {
    let id: String
    let title: String
    let video: SelectedTrainingVideo?
    let unavailableReason: SelectedTrainingVideoUnavailableReason?
    let thumbnailData: Data?
    let preparationProgress: Double?

    var isAvailable: Bool {
        video != nil && unavailableReason == nil
    }

    var isPreparing: Bool {
        preparationProgress != nil
    }

    var canPrepare: Bool {
        video != nil && unavailableReason == .notReady && !isPreparing
    }

    var statusText: String {
        if let preparationProgressText {
            return "准备中 \(preparationProgressText)"
        }

        return unavailableReason?.displayText ?? "可用"
    }

    var unavailableReasonText: String? {
        unavailableReason?.displayText
    }

    var preparationProgressText: String? {
        guard let preparationProgress else {
            return nil
        }

        return "\(Int((Self.clampedProgress(preparationProgress) * 100).rounded()))%"
    }

    func preparing(progress: Double) -> SelectedTrainingVideoSelectionItem {
        SelectedTrainingVideoSelectionItem(
            id: id,
            title: title,
            video: video,
            unavailableReason: unavailableReason,
            thumbnailData: thumbnailData,
            preparationProgress: Self.clampedProgress(progress),
        )
    }

    func availableAfterPreparation() -> SelectedTrainingVideoSelectionItem? {
        guard let video else {
            return nil
        }

        return .available(
            id: id,
            title: title,
            video: video,
            thumbnailData: thumbnailData,
        )
    }

    static func available(
        id: String,
        title: String,
        video: SelectedTrainingVideo,
        thumbnailData: Data?,
    ) -> SelectedTrainingVideoSelectionItem {
        SelectedTrainingVideoSelectionItem(
            id: id,
            title: title,
            video: video,
            unavailableReason: nil,
            thumbnailData: thumbnailData,
            preparationProgress: nil,
        )
    }

    static func unavailable(
        id: String,
        title: String,
        video: SelectedTrainingVideo? = nil,
        reason: SelectedTrainingVideoUnavailableReason,
        thumbnailData: Data?,
    ) -> SelectedTrainingVideoSelectionItem {
        SelectedTrainingVideoSelectionItem(
            id: id,
            title: title,
            video: video,
            unavailableReason: reason,
            thumbnailData: thumbnailData,
            preparationProgress: nil,
        )
    }

    private static func clampedProgress(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

extension Array where Element == SelectedTrainingVideoSelectionItem {
    var availableVideos: [SelectedTrainingVideo] {
        compactMap { item in
            item.isAvailable ? item.video : nil
        }
    }

    func rows(maximumItemsPerRow: Int) -> [[SelectedTrainingVideoSelectionItem]] {
        guard maximumItemsPerRow > 0 else {
            return [self]
        }

        return stride(from: 0, to: count, by: maximumItemsPerRow).map { startIndex in
            Array(self[startIndex..<Swift.min(startIndex + maximumItemsPerRow, count)])
        }
    }
}
