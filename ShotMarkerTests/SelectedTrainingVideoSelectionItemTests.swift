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
}
