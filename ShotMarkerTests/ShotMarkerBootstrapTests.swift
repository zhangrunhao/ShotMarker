@testable import ShotMarker
import SwiftUI
import XCTest

@MainActor
final class ShotMarkerBootstrapTests: XCTestCase {
    func testBackgroundDuringLoadingIsAppliedBeforeServicesStart() async {
        let services = ControlledStartupServices()
        let bootstrap = ShotMarkerBootstrap(reset: { nil }, makeServices: { _ in services })
        let starting = Task { await bootstrap.start() }
        await services.waitUntilLoading()
        bootstrap.updateScenePhase(.background)
        services.finishLoading()
        await starting.value

        XCTAssertFalse(services.foregroundAtStart ?? true)
        XCTAssertNotNil(bootstrap.services)
    }

    func testInactiveDoesNotUndoBackgroundWhileServicesAreLoading() async {
        let services = ControlledStartupServices()
        let bootstrap = ShotMarkerBootstrap(reset: { nil }, makeServices: { _ in services })
        let starting = Task { await bootstrap.start() }
        await services.waitUntilLoading()
        bootstrap.updateScenePhase(.background)
        bootstrap.updateScenePhase(.inactive)
        services.finishLoading()
        await starting.value

        XCTAssertFalse(services.foregroundAtStart ?? true)
    }

    func testReturningActiveBeforeLoadingCompletesStartsInForeground() async {
        let services = ControlledStartupServices()
        let bootstrap = ShotMarkerBootstrap(reset: { nil }, makeServices: { _ in services })
        let starting = Task { await bootstrap.start() }
        await services.waitUntilLoading()
        bootstrap.updateScenePhase(.background)
        bootstrap.updateScenePhase(.active)
        services.finishLoading()
        await starting.value

        XCTAssertEqual(services.foregroundAtStart, true)
        bootstrap.updateScenePhase(.background)
        XCTAssertFalse(services.foreground)
        bootstrap.updateScenePhase(.active)
        XCTAssertTrue(services.foreground)
    }
}

@MainActor
private final class ControlledStartupServices: ShotMarkerServiceLifecycle {
    var foreground = true
    var foregroundAtStart: Bool?
    private var loadContinuation: CheckedContinuation<Void, Never>?
    private var loadingWaiter: CheckedContinuation<Void, Never>?

    func load() async {
        await withCheckedContinuation { continuation in
            loadContinuation = continuation
            loadingWaiter?.resume()
            loadingWaiter = nil
        }
    }

    func waitUntilLoading() async {
        if loadContinuation != nil { return }
        await withCheckedContinuation { loadingWaiter = $0 }
    }

    func finishLoading() {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    func start() { foregroundAtStart = foreground }
    func enterBackground() { foreground = false }
    func enterForeground() { foreground = true }
}
