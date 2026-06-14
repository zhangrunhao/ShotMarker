@testable import ShotMarker
import XCTest

final class SelectedTrainingVideoFilterSummaryTests: XCTestCase {
    func testSummaryKeepsPresentationSilentWhenSomeVideosAreFiltered() {
        let summary = SelectedTrainingVideoFilterSummary(
            requestedItemCount: 3,
            retainedVideoCount: 1,
            failedToLoadCount: 1,
            noMarkerCoverageCount: 1,
        )

        XCTAssertEqual(summary.filteredVideoCount, 2)
        XCTAssertEqual(summary.presentationAction, .none)
    }

    func testSummaryShowsInlineNoticeWhenAllVideosAreFiltered() {
        let summary = SelectedTrainingVideoFilterSummary(
            requestedItemCount: 2,
            retainedVideoCount: 0,
            failedToLoadCount: 1,
            noMarkerCoverageCount: 1,
        )

        XCTAssertEqual(summary.filteredVideoCount, 2)
        XCTAssertEqual(summary.presentationAction, .clearPickerSelection)
        XCTAssertEqual(
            summary.inlineNotice,
            "没有可用视频。已隐藏未下载、未准备好或不覆盖本次训练的视频。",
        )
    }

    func testSummaryKeepsPresentationSilentWhenNoVideosAreFiltered() {
        let summary = SelectedTrainingVideoFilterSummary(
            requestedItemCount: 2,
            retainedVideoCount: 2,
            failedToLoadCount: 0,
            noMarkerCoverageCount: 0,
        )

        XCTAssertEqual(summary.filteredVideoCount, 0)
        XCTAssertEqual(summary.presentationAction, .none)
    }
}
