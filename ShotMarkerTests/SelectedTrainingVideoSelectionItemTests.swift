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
        let items = [
            SelectedTrainingVideoSelectionItem.unavailable(
                id: "item-1",
                title: "视频 1",
                reason: .noMarkerCoverage,
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
}
