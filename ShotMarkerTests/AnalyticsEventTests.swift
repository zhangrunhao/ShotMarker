@testable import ShotMarker
import XCTest

final class AnalyticsEventTests: XCTestCase {
    func testEventRawValuesAreTheApprovedFlowContract() {
        XCTAssertEqual(
            AnalyticsEvent.allCases.map(\.rawValue),
            [
                "app_launch",
                "training_sync_started",
                "training_sync_succeeded",
                "training_sync_failed",
                "training_sync_ignored",
                "training_sync_ack_failed",
                "highlight_generate_started",
                "highlight_generate_succeeded",
                "highlight_generate_failed",
                "highlight_generate_cancelled",
                "highlight_save_started",
                "highlight_save_succeeded",
                "highlight_save_failed",
                "highlight_save_cancelled",
                "highlight_save_state_failed",
            ],
        )
    }
}
