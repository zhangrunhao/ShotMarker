@testable import ShotMarker
import Foundation
import XCTest

final class PrivacyManifestTests: XCTestCase {
    func testCollectedDataTypesExactlyMatchAnalyticsAndDiagnosticsContract() throws {
        let manifest = try loadManifest()
        let entries = try XCTUnwrap(
            manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]],
        )
        let types = entries.compactMap {
            $0["NSPrivacyCollectedDataType"] as? String
        }

        XCTAssertEqual(Set(types), Set([
            "NSPrivacyCollectedDataTypeDeviceID",
            "NSPrivacyCollectedDataTypeProductInteraction",
            "NSPrivacyCollectedDataTypeCrashData",
            "NSPrivacyCollectedDataTypePerformanceData",
            "NSPrivacyCollectedDataTypeOtherDiagnosticData",
        ]))
        XCTAssertEqual(types.count, 5)
    }

    func testAnalyticsDataTypesAreUniqueLinkedForAnalyticsAndNotTracking() throws {
        let manifest = try loadManifest()
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertNil(manifest["NSPrivacyTrackingDomains"])
        let entries = try XCTUnwrap(
            manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]],
        )

        for type in [
            "NSPrivacyCollectedDataTypeDeviceID",
            "NSPrivacyCollectedDataTypeProductInteraction",
        ] {
            let matchingEntries = entries.filter {
                $0["NSPrivacyCollectedDataType"] as? String == type
            }
            XCTAssertEqual(matchingEntries.count, 1)
            let entry = try XCTUnwrap(matchingEntries.first)
            XCTAssertEqual(entry["NSPrivacyCollectedDataTypeLinked"] as? Bool, true)
            XCTAssertEqual(entry["NSPrivacyCollectedDataTypeTracking"] as? Bool, false)
            XCTAssertTrue(
                (entry["NSPrivacyCollectedDataTypePurposes"] as? [String])?
                    .contains("NSPrivacyCollectedDataTypePurposeAnalytics") == true,
            )
        }
    }

    func testDiagnosticDataTypesAreUniqueUnlinkedForAppFunctionalityAndNotTracking() throws {
        let manifest = try loadManifest()
        let entries = try XCTUnwrap(
            manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]],
        )

        for type in [
            "NSPrivacyCollectedDataTypeCrashData",
            "NSPrivacyCollectedDataTypePerformanceData",
            "NSPrivacyCollectedDataTypeOtherDiagnosticData",
        ] {
            let matchingEntries = entries.filter {
                $0["NSPrivacyCollectedDataType"] as? String == type
            }
            XCTAssertEqual(matchingEntries.count, 1)
            let entry = try XCTUnwrap(matchingEntries.first)
            XCTAssertEqual(entry["NSPrivacyCollectedDataTypeLinked"] as? Bool, false)
            XCTAssertEqual(entry["NSPrivacyCollectedDataTypeTracking"] as? Bool, false)
            XCTAssertEqual(
                entry["NSPrivacyCollectedDataTypePurposes"] as? [String],
                ["NSPrivacyCollectedDataTypePurposeAppFunctionality"],
            )
        }
    }

    func testRequiredReasonAPIsCoverAppAndSourceSentryUsage() throws {
        let manifest = try loadManifest()
        let entries = try XCTUnwrap(
            manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]],
        )

        for (type, reason) in [
            ("NSPrivacyAccessedAPICategoryUserDefaults", "CA92.1"),
            ("NSPrivacyAccessedAPICategoryFileTimestamp", "C617.1"),
            ("NSPrivacyAccessedAPICategorySystemBootTime", "35F9.1"),
        ] {
            let matchingEntries = entries.filter {
                $0["NSPrivacyAccessedAPIType"] as? String == type
            }
            XCTAssertEqual(matchingEntries.count, 1)
            let entry = try XCTUnwrap(matchingEntries.first)
            XCTAssertTrue(
                (entry["NSPrivacyAccessedAPITypeReasons"] as? [String])?
                    .contains(reason) == true,
            )
        }
    }

    private func loadManifest() throws -> [String: Any] {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repositoryRoot.appendingPathComponent("ShotMarker/PrivacyInfo.xcprivacy")
        let data = try Data(contentsOf: url)
        let value = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil,
        )
        return try XCTUnwrap(value as? [String: Any])
    }
}
