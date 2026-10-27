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
    func testReleaseSimulatorNeverSends() {
        XCTAssertFalse(AnalyticsRuntimePolicy.shouldSend(isDebugBuild: false, isPhone: true, isSimulator: true))
        XCTAssertFalse(AnalyticsRuntimePolicy.isEnabled)
    }

    func testDistributionRequiresVerifiedMatchingProductionAndKeepsUnknownSafe() {
        let cases: [(Bool, Bool, String?, Bool, AnalyticsDistribution)] = [
            (false, false, nil, false, .unknown),
            (false, false, "Production", false, .unknown),
            (false, false, "unexpected", true, .unknown),
            (false, false, "Production", true, .appStore),
            (false, false, "Sandbox", true, .test),
            (false, false, "Xcode", true, .test),
            (true, false, "Production", true, .test),
            (false, true, nil, false, .test),
        ]
        for (profile, sandbox, environment, matches, expected) in cases {
            XCTAssertEqual(AnalyticsDistribution.classify(hasProvisioningProfile: profile,
                isSandboxReceipt: sandbox, verifiedEnvironment: environment, bundleMatches: matches), expected)
        }
    }
}
