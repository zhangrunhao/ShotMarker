@testable import ShotMarker
import Foundation
import XCTest

final class AnalyticsClientTests: XCTestCase {
    func testMakeRequestUsesExtendedShotMarkerProtocol() throws {
        let client = AnalyticsClient(
            installationIDProvider: StubInstallationIDProvider(value: "AbCd1234Ef56"),
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
                "project": "shotmarker",
                "device_id": "AbCd1234Ef56",
                "event": "highlight_save_succeeded",
                "distribution": "unknown",
                "is_self_use": "false",
                "app_version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                "app_build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            ],
        )
    }

    func testOperationCapturesAudienceAndUsesDedicatedLowercaseID() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defer { defaults.removeObject(forKey: AnalyticsPreferences.selfUseKey) }
        let environment = AnalyticsDistributionBox()
        let client = AnalyticsClient(distribution: { environment.snapshot() }, userDefaults: defaults,
            appVersion: "1.3", appBuild: "42", sendRequest: { _ in })
        let operation = UUID(uuidString: "11111111-2222-4333-A444-555555555555")!
        let first = try query(client.makeRequest(for: .highlightGenerateStarted, operationID: operation, stage: .validation))
        defaults.set(true, forKey: AnalyticsPreferences.selfUseKey)
        environment.setDistribution(.appStore)
        let terminal = try query(client.makeRequest(for: .highlightGenerateFailed, operationID: operation, stage: .export, reason: .exportFailed))
        let later = try query(client.makeRequest(for: .highlightGenerateStarted, operationID: UUID(), stage: .validation))
        XCTAssertEqual(first["distribution"], "unknown")
        XCTAssertEqual(first["is_self_use"], "false")
        XCTAssertEqual(terminal["distribution"], "unknown")
        XCTAssertEqual(terminal["is_self_use"], "false")
        XCTAssertEqual(terminal["operation_id"], "11111111-2222-4333-a444-555555555555")
        XCTAssertEqual(terminal["stage"], "export")
        XCTAssertEqual(terminal["reason"], "export_failed")
        XCTAssertEqual(later["distribution"], "app_store")
        XCTAssertEqual(later["is_self_use"], "true")
        XCTAssertEqual(Set(terminal.keys), ["project", "event", "device_id", "distribution", "is_self_use", "app_version", "app_build", "operation_id", "stage", "reason"])
    }

    func testVersionValidationAndLaunchOmitOperationDetails() throws {
        let client = AnalyticsClient(appVersion: "1.2/private", appBuild: "1.2", sendRequest: { _ in })
        let values = try query(client.makeRequest(for: .appLaunch, operationID: UUID(), stage: .validation, reason: .unknown))
        XCTAssertEqual(values["app_version"], "unknown")
        XCTAssertEqual(values["app_build"], "unknown")
        XCTAssertNil(values["operation_id"])
        XCTAssertNil(values["stage"])
        XCTAssertNil(values["reason"])
        let long = AnalyticsClient(appVersion: String(repeating: "1", count: 33), appBuild: "", sendRequest: { _ in })
        XCTAssertEqual(try query(long.makeRequest(for: .appLaunch))["app_version"], "unknown")
        XCTAssertEqual(try query(long.makeRequest(for: .appLaunch))["app_build"], "unknown")
    }

    private func query(_ request: URLRequest?) throws -> [String: String] {
        let request = try XCTUnwrap(request)
        let items = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems)
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    func testDistributionResolutionDoesNotBlockCallerOrChangeAudienceMidOperation() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defer { defaults.removeObject(forKey: AnalyticsPreferences.selfUseKey) }
        let gate = AnalyticsDistributionGate()
        let recorder = AnalyticsRequestRecorder()
        let client = AnalyticsClient(resolveDistribution: { await gate.value() }, userDefaults: defaults,
            sendRequest: { await recorder.record($0) })
        let operation = UUID()
        client.track(.highlightSaveStarted, operationID: operation, stage: .validation)
        defaults.set(true, forKey: AnalyticsPreferences.selfUseKey)
        client.track(.highlightSaveSucceeded, operationID: operation, stage: .photosWrite)
        let beforeResolution = await recorder.snapshot()
        XCTAssertTrue(beforeResolution.isEmpty)
        await gate.release()
        var requests: [URLRequest] = []
        for _ in 0..<100 {
            requests = await recorder.snapshot()
            if requests.count == 2 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(requests.count, 2)
        for request in requests {
            let values = try query(request)
            XCTAssertEqual(values["distribution"], "app_store")
            XCTAssertEqual(values["is_self_use"], "false")
            XCTAssertEqual(values["operation_id"], operation.uuidString.lowercased())
        }
    }

    func testTrackSchedulesExactlyOneRequestWithoutRetry() async throws {
        let recorder = AnalyticsRequestRecorder()
        let client = AnalyticsClient(
            installationIDProvider: StubInstallationIDProvider(value: "AbCd1234Ef56"),
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

nonisolated private final class AnalyticsDistributionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var distribution: AnalyticsDistribution = .unknown
    func setDistribution(_ value: AnalyticsDistribution) { lock.withLock { distribution = value } }
    func snapshot() -> AnalyticsDistribution { lock.withLock { distribution } }
}

private actor AnalyticsDistributionGate {
    private var ready = false
    private var waiters: [CheckedContinuation<AnalyticsDistribution, Never>] = []
    func value() async -> AnalyticsDistribution {
        if ready { return .appStore }
        return await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        ready = true
        for waiter in waiters { waiter.resume(returning: .appStore) }
        waiters.removeAll()
    }
}
