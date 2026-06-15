import Foundation

struct HighlightJobRowViewData: Identifiable, Equatable {
    let id: UUID
    let title: String
    let statusText: String
    let progressFraction: Double?
    let showsCancel: Bool
    let showsRestart: Bool
    let showsPlay: Bool
    let showsSave: Bool
    let showsClear: Bool

    init(job: HighlightJob, isSavingToPhotoLibrary: Bool = false) {
        id = job.id
        title = job.trainingSession.markerTimeRange.startedAt.formatted(.dateTime.month().day().hour().minute())
        statusText = Self.statusText(for: job, isSavingToPhotoLibrary: isSavingToPhotoLibrary)
        progressFraction = job.status == .queued || job.status == .running ? job.progress.fractionCompleted : nil
        showsCancel = job.status == .queued || job.status == .running || job.status == .saving
        showsRestart = job.status == .failed || job.status == .interrupted
        showsPlay = job.status == .completed
        showsSave = job.status == .completed
            && !isSavingToPhotoLibrary
            && job.outputVideoPath != nil
        showsClear = job.status == .completed || job.status == .failed || job.status == .interrupted
    }

    private static func statusText(for job: HighlightJob, isSavingToPhotoLibrary: Bool) -> String {
        switch job.status {
        case .queued:
            "等待中"
        case .running:
            if job.progress.totalMarkerCount > 0 {
                "正在生成 \(job.progress.completedMarkerCount)/\(job.progress.totalMarkerCount)"
            } else {
                "正在生成"
            }
        case .saving:
            "正在保存到相册"
        case .completed:
            if isSavingToPhotoLibrary {
                "正在保存到相册"
            } else if let photoLibrarySaveErrorMessage = job.photoLibrarySaveErrorMessage {
                photoLibrarySaveErrorMessage
            } else if job.photoLibrarySavedAt != nil {
                "已保存到相册"
            } else {
                "已完成"
            }
        case .failed:
            job.errorMessage ?? "集锦生成失败"
        case .interrupted:
            "已中断，可重新开始"
        }
    }
}
