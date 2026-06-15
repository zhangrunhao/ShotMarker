@testable import ShotMarker
import XCTest

final class HighlightJobRowViewDataTests: XCTestCase {
    func testSaveActionConfirmationRequestsExplicitSaveApproval() throws {
        let jobID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000050010"))

        let confirmation = HighlightJobActionConfirmation.save(jobID: jobID)

        XCTAssertEqual(confirmation.id, "save-\(jobID.uuidString)")
        XCTAssertEqual(confirmation.action, .save(jobID))
        XCTAssertEqual(confirmation.jobID, jobID)
        XCTAssertEqual(confirmation.title, "保存到相册？")
        XCTAssertEqual(confirmation.message, "会将这个集锦视频保存到系统相册。")
        XCTAssertEqual(confirmation.confirmButtonTitle, "保存")
        XCTAssertFalse(confirmation.isDestructive)
    }

    func testClearActionConfirmationRequestsDestructiveDeleteApproval() throws {
        let jobID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000050011"))

        let confirmation = HighlightJobActionConfirmation.clear(jobID: jobID)

        XCTAssertEqual(confirmation.id, "clear-\(jobID.uuidString)")
        XCTAssertEqual(confirmation.action, .clear(jobID))
        XCTAssertEqual(confirmation.jobID, jobID)
        XCTAssertEqual(confirmation.title, "删除任务？")
        XCTAssertEqual(confirmation.message, "会从首页移除这个集锦任务，并清理它的本地视频文件。")
        XCTAssertEqual(confirmation.confirmButtonTitle, "删除")
        XCTAssertTrue(confirmation.isDestructive)
    }

    func testRunningJobShowsProgressAndCancelAction() throws {
        let row = HighlightJobRowViewData(
            job: try makeJob(
                status: .running,
                progress: HighlightJobProgress(completedMarkerCount: 3, totalMarkerCount: 10),
            ),
        )

        XCTAssertEqual(row.statusText, "正在生成 3/10")
        XCTAssertEqual(row.progressFraction, 0.3)
        XCTAssertEqual(row.actionLayout, .compact)
        XCTAssertTrue(row.showsCancel)
        XCTAssertFalse(row.showsRestart)
        XCTAssertFalse(row.showsPlay)
    }

    func testCompletedJobShowsPlaySaveAndClearActions() throws {
        let row = HighlightJobRowViewData(job: try makeJob(status: .completed))

        XCTAssertEqual(row.statusText, "已完成")
        XCTAssertNil(row.progressFraction)
        XCTAssertEqual(row.actionLayout, .completedActionBar)
        XCTAssertTrue(row.showsPlay)
        XCTAssertTrue(row.showsSave)
        XCTAssertTrue(row.showsClear)
    }

    func testCompletedSavedJobStillShowsSaveAction() throws {
        var job = try makeJob(status: .completed)
        job.photoLibrarySavedAt = Date(timeIntervalSince1970: 4_000)

        let row = HighlightJobRowViewData(job: job)

        XCTAssertEqual(row.statusText, "已保存到相册")
        XCTAssertEqual(row.actionLayout, .completedActionBar)
        XCTAssertTrue(row.showsPlay)
        XCTAssertTrue(row.showsSave)
        XCTAssertTrue(row.showsClear)
    }

    func testCompletedJobShowsPhotoLibrarySaveFailureAndRetryAction() throws {
        var job = try makeJob(status: .completed)
        job.photoLibrarySaveErrorMessage = "没有相册保存权限。请允许 ShotMarker 添加照片后再试。"

        let row = HighlightJobRowViewData(job: job)

        XCTAssertEqual(row.statusText, "没有相册保存权限。请允许 ShotMarker 添加照片后再试。")
        XCTAssertTrue(row.showsSave)
    }

    func testCompletedJobSavingToPhotoLibraryShowsSavingText() throws {
        let row = HighlightJobRowViewData(job: try makeJob(status: .completed), isSavingToPhotoLibrary: true)

        XCTAssertEqual(row.statusText, "正在保存到相册")
        XCTAssertEqual(row.actionLayout, .compact)
        XCTAssertTrue(row.showsPlay)
        XCTAssertFalse(row.showsSave)
        XCTAssertTrue(row.showsClear)
    }

    func testInterruptedJobShowsRestartAndClearActions() throws {
        let row = HighlightJobRowViewData(job: try makeJob(status: .interrupted))

        XCTAssertEqual(row.statusText, "已中断，可重新开始")
        XCTAssertTrue(row.showsRestart)
        XCTAssertTrue(row.showsClear)
    }

    func testFailedJobShowsErrorMessage() throws {
        var job = try makeJob(status: .failed)
        job.errorMessage = "视频已生成，但保存到相册失败。"

        let row = HighlightJobRowViewData(job: job)

        XCTAssertEqual(row.statusText, "视频已生成，但保存到相册失败。")
        XCTAssertTrue(row.showsRestart)
        XCTAssertTrue(row.showsClear)
    }

    private func makeJob(
        status: HighlightJobStatus,
        progress: HighlightJobProgress = .zero,
    ) throws -> HighlightJob {
        HighlightJob(
            id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000050001")),
            trainingSession: TrainingSession(
                id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000050100")),
                startedAt: Date(timeIntervalSince1970: 2_000),
                endedAt: Date(timeIntervalSince1970: 2_600),
                events: [],
            ),
            selectedVideos: [],
            clipSettings: ClipSettings(secondsBeforeMarker: 9, secondsAfterMarker: 4),
            status: status,
            progress: progress,
            outputVideoPath: status == .completed ? "HighlightJobs/Outputs/job/highlight.mov" : nil,
            errorMessage: nil,
            createdAt: Date(timeIntervalSince1970: 3_000),
            updatedAt: Date(timeIntervalSince1970: 3_000),
        )
    }
}
