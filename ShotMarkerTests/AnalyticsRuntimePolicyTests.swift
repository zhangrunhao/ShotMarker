@testable import ShotMarker
import XCTest

final class AnalyticsRuntimePolicyTests: XCTestCase {
    func testOnlyReleaseIPhoneSendsAnalytics() {
        XCTAssertTrue(
            AnalyticsRuntimePolicy.shouldSend(isDebugBuild: false, isPhone: true),
        )
        XCTAssertFalse(
            AnalyticsRuntimePolicy.shouldSend(isDebugBuild: true, isPhone: true),
        )
        XCTAssertFalse(
            AnalyticsRuntimePolicy.shouldSend(isDebugBuild: false, isPhone: false),
        )
        XCTAssertFalse(
            AnalyticsRuntimePolicy.shouldSend(isDebugBuild: true, isPhone: false),
        )
    }
}
