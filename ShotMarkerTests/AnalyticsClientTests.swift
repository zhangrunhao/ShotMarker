@testable import ShotMarker
import Foundation
import XCTest

final class AnalyticsClientTests: XCTestCase {
    func testMakeRequestUsesTheFixedShotMarkerSchema() throws {
        let client = AnalyticsClient(
            installationIDProvider: StubInstallationIDProvider(value: "AbCd1234Ef56"),
            now: { Date(timeIntervalSince1970: 20_000) },
            sendRequest: { _ in },
        )

        let request = try XCTUnwrap(client.makeRequest(for: .highlightSaveSucceeded))
        let components = try XCTUnwrap(
            URLComponents(url: request.url!, resolvingAgainstBaseURL: false),
        )
        let query = Dictionary(
            uniqueKeysWithValues: try XCTUnwrap(components.queryItems).map {
                ($0.name, $0.value ?? "")
            },
        )

        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "zhangrh.shop")
        XCTAssertEqual(components.path, "/track")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(request.timeoutInterval, 5)
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertEqual(
            query,
            [
                "time": "20000000",
                "project": "shotmarker",
                "device_id": "AbCd1234Ef56",
                "event": "highlight_save_succeeded",
                "params": "{}",
            ],
        )
    }

    func testTrackSchedulesExactlyOneRequestWithoutRetry() async throws {
        let recorder = AnalyticsRequestRecorder()
        let client = AnalyticsClient(
            installationIDProvider: StubInstallationIDProvider(value: "AbCd1234Ef56"),
            now: { Date(timeIntervalSince1970: 20_000) },
            sendRequest: { request in
                await recorder.record(request)
            },
        )

        client.track(.appLaunch)

        var requests: [URLRequest] = []
        for _ in 0 ..< 100 {
            requests = await recorder.snapshot()
            if !requests.isEmpty {
                break
            }
            await Task.yield()
        }
        XCTAssertEqual(requests.count, 1)
        let sentRequest = try XCTUnwrap(requests.first)
        XCTAssertEqual(
            URLComponents(url: sentRequest.url!, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "event" })?
                .value,
            "app_launch",
        )

        for _ in 0 ..< 20 {
            await Task.yield()
        }
        let finalRequests = await recorder.snapshot()
        XCTAssertEqual(finalRequests.count, 1)
    }
}

private struct StubInstallationIDProvider: InstallationIDProviding {
    let value: String

    func installationID() -> String {
        value
    }
}

private actor AnalyticsRequestRecorder {
    private var requests: [URLRequest] = []

    func record(_ request: URLRequest) {
        requests.append(request)
    }

    func snapshot() -> [URLRequest] {
        requests
    }
}
