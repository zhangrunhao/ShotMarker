@testable import ShotMarker
import Sentry
import XCTest

final class GlitchTipConfigurationTests: XCTestCase {
    func testMissingDSNDisablesConfiguration() {
        XCTAssertNil(GlitchTipConfiguration.load(infoDictionary: [:]))
    }

    func testEmptyDSNDisablesConfiguration() {
        XCTAssertNil(GlitchTipConfiguration.load(infoDictionary: [
            GlitchTipConfiguration.infoDictionaryKey: "   ",
        ]))
    }

    func testNonGlitchTipHostDisablesConfiguration() {
        XCTAssertNil(GlitchTipConfiguration.load(infoDictionary: [
            GlitchTipConfiguration.infoDictionaryKey: "https://public@example.com/4",
        ]))
    }

    func testValidDSNLoadsConfiguration() {
        let configuration = GlitchTipConfiguration.load(
            infoDictionary: [
                GlitchTipConfiguration.infoDictionaryKey:
                    "  https://public-key@glitchtip.zhangrh.shop/4  ",
            ],
            environment: "test",
        )

        XCTAssertEqual(configuration, GlitchTipConfiguration(
            dsn: "https://public-key@glitchtip.zhangrh.shop/4",
            environment: "test",
        ))
    }

    func testRemoteErrorEventOnlyContainsAllowlistedMetadata() throws {
        let logEvent = AppLogEvent(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 123),
            level: .error,
            category: .video,
            name: "video.export.failed",
            message: "视频导出失败",
            context: [
                "jobID": "private-job-id",
                "path": "/private/video.mov",
            ],
            errorDomain: "AVFoundationErrorDomain",
            errorCode: -1,
            errorDescription: "Private error description",
        )

        let remoteEvent = GlitchTipErrorReporter.makeRemoteEvent(from: logEvent)

        XCTAssertEqual(remoteEvent.level, .error)
        XCTAssertEqual(remoteEvent.timestamp, logEvent.timestamp)
        XCTAssertEqual(remoteEvent.message?.formatted, "视频导出失败")
        XCTAssertEqual(remoteEvent.tags?["app.error.name"], "video.export.failed")
        XCTAssertEqual(remoteEvent.tags?["app.error.category"], "video")
        XCTAssertEqual(remoteEvent.tags?["error.domain"], "AVFoundationErrorDomain")
        XCTAssertEqual(remoteEvent.tags?["error.code"], "-1")
        XCTAssertEqual(remoteEvent.fingerprint, [
            "video.export.failed",
            "AVFoundationErrorDomain",
            "-1",
        ])
        XCTAssertNil(remoteEvent.extra)
        XCTAssertFalse(remoteEvent.message?.formatted.contains("private-job-id") == true)
        XCTAssertFalse(remoteEvent.message?.formatted.contains("Private error description") == true)
    }
}
