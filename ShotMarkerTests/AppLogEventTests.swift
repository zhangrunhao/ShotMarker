@testable import ShotMarker
import XCTest

final class AppLogEventTests: XCTestCase {
    func testAppLogEventJSONRoundTripsAllFields() throws {
        let event = AppLogEvent(
            id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000101")),
            timestamp: Date(timeIntervalSince1970: 1_778_400_000),
            level: .warning,
            category: .video,
            name: "highlight.generate.started",
            message: "开始生成集锦",
            context: [
                "matchedMarkerCount": "9",
                "selectedVideoCount": "1",
            ],
            errorDomain: "ShotMarkerTests",
            errorCode: 42,
            errorDescription: "Example error",
        )

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(AppLogEvent.self, from: data)

        XCTAssertEqual(decoded, event)
        XCTAssertEqual(AppLogLevel.debug.rawValue, "debug")
        XCTAssertEqual(AppLogLevel.info.rawValue, "info")
        XCTAssertEqual(AppLogLevel.warning.rawValue, "warning")
        XCTAssertEqual(AppLogLevel.error.rawValue, "error")
        XCTAssertEqual(AppLogCategory.app.rawValue, "app")
        XCTAssertEqual(AppLogCategory.training.rawValue, "training")
        XCTAssertEqual(AppLogCategory.sync.rawValue, "sync")
        XCTAssertEqual(AppLogCategory.video.rawValue, "video")
        XCTAssertEqual(AppLogCategory.photos.rawValue, "photos")
        XCTAssertEqual(AppLogCategory.diagnostics.rawValue, "diagnostics")
    }

    func testAppLogEventCapturesNSErrorMetadata() throws {
        let error = NSError(
            domain: "ShotMarkerTestDomain",
            code: 3169,
            userInfo: [NSLocalizedDescriptionKey: "Cannot load selected video"],
        )

        let event = AppLogEvent.make(
            id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000102")),
            timestamp: Date(timeIntervalSince1970: 1_778_400_100),
            level: .error,
            category: .video,
            name: "video.selection.failed",
            message: "视频读取失败",
            context: ["trainingSessionId": "session-1"],
            error: error,
        )

        XCTAssertEqual(event.errorDomain, "ShotMarkerTestDomain")
        XCTAssertEqual(event.errorCode, 3169)
        XCTAssertEqual(event.errorDescription, "Cannot load selected video")
    }
}
