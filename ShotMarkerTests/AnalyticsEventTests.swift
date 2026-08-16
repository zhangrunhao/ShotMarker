@testable import ShotMarker
import XCTest

final class AnalyticsEventTests: XCTestCase {
    func testEventRawValuesAreTheApprovedFourEventContract() {
        XCTAssertEqual(
            AnalyticsEvent.allCases.map(\.rawValue),
            [
                "app_launch",
                "training_sync_succeeded",
                "highlight_generate_succeeded",
                "highlight_save_succeeded",
            ],
        )
    }
}
