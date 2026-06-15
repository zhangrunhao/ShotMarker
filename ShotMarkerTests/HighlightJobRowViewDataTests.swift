@testable import ShotMarker
import XCTest

final class HighlightJobRowViewDataTests: XCTestCase {
    func testRunningJobShowsProgressAndCancelAction() throws {
        let row = HighlightJobRowViewData(
            job: try makeJob(
                status: .running,
                progress: HighlightJobProgress(completedMarkerCount: 3, totalMarkerCount: 10),
            ),
        )

        XCTAssertEqual(row.statusText, "正在生成 3/10")
        XCTAssertEqual(row.progressFraction, 0.3)
        XCTAssertTrue(row.showsCancel)
        XCTAssertFalse(row.showsRestart)
        XCTAssertFalse(row.showsPlay)
    }

    func testCompletedJobShowsPlayAndClearActions() throws {
        let row = HighlightJobRowViewData(job: try makeJob(status: .completed))

        XCTAssertEqual(row.statusText, "已完成")
        XCTAssertNil(row.progressFraction)
        XCTAssertTrue(row.showsPlay)
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
