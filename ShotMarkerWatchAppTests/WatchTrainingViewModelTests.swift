@testable import ShotMarkerWatchApp
import SwiftUI
import XCTest

final class WatchTrainingViewModelTests: XCTestCase {
    func testInitialStateIsNotTraining() {
        let viewModel = WatchTrainingViewModel()

        XCTAssertEqual(viewModel.state, .notTraining)
        XCTAssertEqual(viewModel.buttonTitle, "长按开始")
        XCTAssertEqual(viewModel.buttonColor, .green)
        XCTAssertEqual(viewModel.markerCount, 0)
        XCTAssertEqual(viewModel.markerCountText, "打点数: 0")
    }

    func testLongPressStartsTrainingFromNotTrainingState() {
        let viewModel = WatchTrainingViewModel(now: { Date(timeIntervalSince1970: 1000) })

        let payload = viewModel.handleLongPress()

        XCTAssertNil(payload)
        XCTAssertEqual(viewModel.state, .training)
        XCTAssertEqual(viewModel.startedAt, Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(viewModel.buttonTitle, "双击打点 / 长按结束")
        XCTAssertEqual(viewModel.buttonColor, .red)
        XCTAssertEqual(viewModel.markerCountText, "打点数: 0")
    }

    func testLongPressStartsWorkoutRuntimeFromNotTrainingState() {
        // 这个测试只关心 ViewModel 是否把“开始训练”事件转发给 runtime manager。
        // 真正的 HKWorkoutSession 很难在单测中稳定验证，所以用 spy 记录调用时间。
        let runtimeSessionManager = SpyWatchTrainingRuntimeSessionManager()
        let viewModel = WatchTrainingViewModel(
            now: { Date(timeIntervalSince1970: 1000) },
            runtimeSessionManager: runtimeSessionManager,
        )

        viewModel.handleLongPress()

        XCTAssertEqual(runtimeSessionManager.startedAt, [Date(timeIntervalSince1970: 1000)])
        XCTAssertEqual(runtimeSessionManager.endedAt, [])
    }

    func testLongPressEndsTrainingFromTrainingState() throws {
        var dates = [
            Date(timeIntervalSince1970: 1000),
            Date(timeIntervalSince1970: 1120),
            Date(timeIntervalSince1970: 1600),
        ]
        let sessionId = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000301"))
        let eventId = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000302"))
        var ids = [
            sessionId,
            eventId,
        ]
        let viewModel = WatchTrainingViewModel(
            now: { dates.removeFirst() },
            idFactory: { ids.removeFirst() },
        )

        viewModel.handleLongPress()
        viewModel.handleDoubleTap()
        let payload = viewModel.handleLongPress()

        XCTAssertEqual(viewModel.state, .notTraining)
        XCTAssertEqual(viewModel.endedAt, Date(timeIntervalSince1970: 1600))
        XCTAssertEqual(viewModel.buttonTitle, "长按开始")
        XCTAssertEqual(viewModel.buttonColor, .green)
        XCTAssertEqual(viewModel.markerCount, 0)
        XCTAssertEqual(viewModel.markerCountText, "打点数: 0")
        XCTAssertEqual(
            payload,
            TrainingSessionSyncPayload(
                id: sessionId,
                startedAt: Date(timeIntervalSince1970: 1000),
                endedAt: Date(timeIntervalSince1970: 1600),
                events: [
                    ShotMarkerEventSyncPayload(
                        id: eventId,
                        markedAt: Date(timeIntervalSince1970: 1120),
                    ),
                ],
            ),
        )
    }

    func testLongPressEndsWorkoutRuntimeFromTrainingState() {
        // 用确定性的时间序列验证开始/结束 runtime 的时间与训练状态机使用的时间一致。
        // 这能防止以后有人改成重新 Date()，导致同步 payload 和系统 workout session 时间漂移。
        var dates = [
            Date(timeIntervalSince1970: 1000),
            Date(timeIntervalSince1970: 1600),
        ]
        let runtimeSessionManager = SpyWatchTrainingRuntimeSessionManager()
        let viewModel = WatchTrainingViewModel(
            now: { dates.removeFirst() },
            runtimeSessionManager: runtimeSessionManager,
        )

        viewModel.handleLongPress()
        viewModel.handleLongPress()

        XCTAssertEqual(runtimeSessionManager.startedAt, [Date(timeIntervalSince1970: 1000)])
        XCTAssertEqual(runtimeSessionManager.endedAt, [Date(timeIntervalSince1970: 1600)])
    }

    func testLongPressEndingTrainingEnqueuesCompletedPayloadForSync() throws {
        var dates = [
            Date(timeIntervalSince1970: 1000),
            Date(timeIntervalSince1970: 1120),
            Date(timeIntervalSince1970: 1600),
        ]
        let sessionId = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000601"))
        let eventId = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000602"))
        var ids = [
            sessionId,
            eventId,
        ]
        let syncService = SpyWatchTrainingSyncService()
        let viewModel = WatchTrainingViewModel(
            now: { dates.removeFirst() },
            idFactory: { ids.removeFirst() },
        )

        viewModel.handleLongPress(syncService: syncService)
        viewModel.handleDoubleTap()
        viewModel.handleLongPress(syncService: syncService)

        XCTAssertEqual(syncService.enqueuedPayloads, [
            TrainingSessionSyncPayload(
                id: sessionId,
                startedAt: Date(timeIntervalSince1970: 1000),
                endedAt: Date(timeIntervalSince1970: 1600),
                events: [
                    ShotMarkerEventSyncPayload(
                        id: eventId,
                        markedAt: Date(timeIntervalSince1970: 1120),
                    ),
                ],
            ),
        ])
    }

    func testLongPressEndingTrainingIgnoresSyncFailure() {
        var dates = [
            Date(timeIntervalSince1970: 1000),
            Date(timeIntervalSince1970: 1600),
        ]
        let syncService = SpyWatchTrainingSyncService(error: SyncError.failed)
        let viewModel = WatchTrainingViewModel(now: { dates.removeFirst() })

        viewModel.handleLongPress()
        viewModel.handleLongPress(syncService: syncService)

        XCTAssertEqual(viewModel.state, .notTraining)
        XCTAssertEqual(viewModel.markerCount, 0)
    }

    func testDoubleTapDoesNothingWhenNotTraining() {
        let viewModel = WatchTrainingViewModel(now: { Date(timeIntervalSince1970: 2000) })

        let didRecord = viewModel.handleDoubleTap()

        XCTAssertFalse(didRecord)
        XCTAssertEqual(viewModel.markers, [])
    }

    func testDoubleTapRecordsMarkerWhenStarted() {
        var dates = [
            Date(timeIntervalSince1970: 1000),
            Date(timeIntervalSince1970: 1120),
        ]
        let viewModel = WatchTrainingViewModel(now: { dates.removeFirst() })

        viewModel.handleLongPress()
        let didRecord = viewModel.handleDoubleTap()

        XCTAssertTrue(didRecord)
        XCTAssertEqual(viewModel.markers, [Date(timeIntervalSince1970: 1120)])
        XCTAssertEqual(viewModel.markerCount, 1)
        XCTAssertEqual(viewModel.markerCountText, "打点数: 1")
    }

    func testCrownMarkerThresholdDoesNotTriggerBeforeThreshold() {
        var tracker = CrownMarkerThresholdTracker(threshold: 8, baseline: 0)

        let didTrigger = tracker.update(currentValue: 7.9)

        XCTAssertFalse(didTrigger)
        XCTAssertEqual(tracker.baseline, 0)
    }

    func testCrownMarkerThresholdTriggersAtPositiveThresholdAndResetsBaseline() {
        var tracker = CrownMarkerThresholdTracker(threshold: 8, baseline: 0)

        let didTrigger = tracker.update(currentValue: 8)

        XCTAssertTrue(didTrigger)
        XCTAssertEqual(tracker.baseline, 8)
        XCTAssertFalse(tracker.update(currentValue: 8))
    }

    func testCrownMarkerThresholdTriggersAtNegativeThresholdAndResetsBaseline() {
        var tracker = CrownMarkerThresholdTracker(threshold: 8, baseline: 20)

        let didTrigger = tracker.update(currentValue: 12)

        XCTAssertTrue(didTrigger)
        XCTAssertEqual(tracker.baseline, 12)
        XCTAssertFalse(tracker.update(currentValue: 12))
    }

    func testCrownMarkerThresholdCanResetWhenTrainingStateChanges() {
        var tracker = CrownMarkerThresholdTracker(threshold: 8, baseline: 0)

        tracker.reset(baseline: 100)

        XCTAssertEqual(tracker.baseline, 100)
        XCTAssertFalse(tracker.update(currentValue: 107.9))
        XCTAssertTrue(tracker.update(currentValue: 108))
    }
}

private enum SyncError: Error {
    case failed
}

// 只记录调用，不模拟 HealthKit 行为。这样测试验证的是 ViewModel 和 runtime manager
// 的协作契约，而不是把 HealthKit 框架的细节复制到测试里。
private final class SpyWatchTrainingRuntimeSessionManager: WatchTrainingRuntimeSessionManaging {
    private(set) var startedAt: [Date] = []
    private(set) var endedAt: [Date] = []

    func startTraining(at startDate: Date) {
        startedAt.append(startDate)
    }

    func endTraining(at endDate: Date) {
        endedAt.append(endDate)
    }
}

private final class SpyWatchTrainingSyncService: WatchTrainingSyncServiceProtocol {
    private let error: Error?
    private(set) var enqueuedPayloads: [TrainingSessionSyncPayload] = []

    init(error: Error? = nil) {
        self.error = error
    }

    func enqueueCompletedSession(_ payload: TrainingSessionSyncPayload) throws {
        if let error {
            throw error
        }

        enqueuedPayloads.append(payload)
    }

    func diagnosticsSnapshot() -> WatchTrainingSyncDiagnosticsSnapshot {
        WatchTrainingSyncDiagnosticsSnapshot(
            activationState: "notActivated",
            outboxCount: 0,
            pendingTransferCount: 0,
            awaitingAckCount: 0,
            lastActivationCompletedAt: nil,
            lastRetryAt: nil,
            lastEnqueuedAt: nil,
            lastEnqueuedTrainingSessionId: nil,
            lastTransferRequestedAt: nil,
            lastTransferRequestedTrainingSessionId: nil,
            lastTransferFinishedAt: nil,
            lastTransferFinishedTrainingSessionId: nil,
            lastTransferErrorDescription: nil,
            lastAckReceivedAt: nil,
            lastAckTrainingSessionId: nil,
            lastOutboxErrorDescription: nil,
        )
    }
}
