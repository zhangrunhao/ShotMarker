@testable import ShotMarker
import XCTest

final class SelectedTrainingVideoSelectionItemTests: XCTestCase {
    func testAvailableItemExposesVideoAndStatusText() {
        let video = SelectedTrainingVideo(
            id: "available-video",
            recordedStartAt: Date(timeIntervalSince1970: 100),
            duration: 60,
        )
        let item = SelectedTrainingVideoSelectionItem.available(
            id: "item-1",
            title: "视频 1",
            video: video,
            thumbnailData: Data([1, 2, 3]),
        )

        XCTAssertTrue(item.isAvailable)
        XCTAssertEqual(item.video, video)
        XCTAssertEqual(item.statusText, "可用")
        XCTAssertNil(item.unavailableReasonText)
    }

    func testUnavailableItemExposesReasonText() {
        let item = SelectedTrainingVideoSelectionItem.unavailable(
            id: "item-2",
            title: "视频 2",
            reason: .notReady,
            thumbnailData: nil,
        )

        XCTAssertFalse(item.isAvailable)
        XCTAssertNil(item.video)
        XCTAssertEqual(item.statusText, "未下载或未准备好")
        XCTAssertEqual(item.unavailableReasonText, "未下载或未准备好")
    }

    func testSelectionItemsExposeOnlyAvailableVideos() {
        let availableVideo = SelectedTrainingVideo(
            id: "available-video",
            recordedStartAt: Date(timeIntervalSince1970: 100),
            duration: 60,
        )
        let unavailableVideo = SelectedTrainingVideo(
            id: "unavailable-video",
            recordedStartAt: Date(timeIntervalSince1970: 200),
            duration: 60,
        )
        let items = [
            SelectedTrainingVideoSelectionItem.unavailable(
                id: "item-1",
                title: "视频 1",
                reason: .noMarkerCoverage,
                thumbnailData: nil,
            ),
            SelectedTrainingVideoSelectionItem.unavailable(
                id: "item-3",
                title: "视频 3",
                video: unavailableVideo,
                reason: .notReady,
                thumbnailData: nil,
            ),
            SelectedTrainingVideoSelectionItem.available(
                id: "item-2",
                title: "视频 2",
                video: availableVideo,
                thumbnailData: nil,
            ),
        ]

        XCTAssertEqual(items.availableVideos, [availableVideo])
    }

    func testSelectionItemsWrapIntoRowsWithoutDroppingVideos() {
        let items = (1...5).map { index in
            SelectedTrainingVideoSelectionItem.unavailable(
                id: "item-\(index)",
                title: "视频 \(index)",
                reason: .notReady,
                thumbnailData: nil,
            )
        }

        let rows = items.rows(maximumItemsPerRow: 2)

        XCTAssertEqual(rows.map { $0.map(\.id) }, [
            ["item-1", "item-2"],
            ["item-3", "item-4"],
            ["item-5"],
        ])
    }

    func testNotReadyItemCanShowPreparationProgress() {
        let video = SelectedTrainingVideo(
            id: "not-ready-video",
            recordedStartAt: Date(timeIntervalSince1970: 100),
            duration: 60,
        )
        let item = SelectedTrainingVideoSelectionItem.unavailable(
            id: "item-1",
            title: "视频 1",
            video: video,
            reason: .notReady,
            thumbnailData: nil,
        )

        let preparingItem = item.preparing(progress: 0.426)

        XCTAssertTrue(item.canPrepare)
        XCTAssertFalse(item.isPreparing)
        XCTAssertTrue(preparingItem.isPreparing)
        XCTAssertFalse(preparingItem.canPrepare)
        XCTAssertEqual(preparingItem.preparationProgressText, "43%")
        XCTAssertEqual(preparingItem.statusText, "准备中 43%")
    }

    func testPreparedItemBecomesAvailable() throws {
        let video = SelectedTrainingVideo(
            id: "not-ready-video",
            recordedStartAt: Date(timeIntervalSince1970: 100),
            duration: 60,
        )
        let item = SelectedTrainingVideoSelectionItem.unavailable(
            id: "item-1",
            title: "视频 1",
            video: video,
            reason: .notReady,
            thumbnailData: Data([1]),
        )

        let availableItem = try XCTUnwrap(item.availableAfterPreparation())

        XCTAssertTrue(availableItem.isAvailable)
        XCTAssertEqual(availableItem.video, video)
        XCTAssertEqual(availableItem.thumbnailData, Data([1]))
        XCTAssertEqual([availableItem].availableVideos, [video])
    }
}
