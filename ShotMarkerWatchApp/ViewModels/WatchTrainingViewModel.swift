import Combine
import Foundation
import SwiftUI

enum WatchTrainingState: Equatable {
    case notTraining
    case training
}

@MainActor
final class WatchTrainingViewModel: ObservableObject {
    @Published private(set) var state: WatchTrainingState = .notTraining
    @Published private(set) var startedAt: Date?
    @Published private(set) var endedAt: Date?
    @Published private(set) var markers: [Date] = []

    private let now: () -> Date
    private let idFactory: () -> UUID

    // 训练状态变化和系统 runtime 生命周期必须绑定在一起：
    // - 从 notTraining 进入 training 时启动 workout runtime，让 watchOS 知道这是一次训练；
    // - 从 training 回到 notTraining 时停止 runtime，释放系统后台运行资格。
    // 这里依赖协议而不是 HealthKit 具体类，是为了让 ViewModel 的状态机可测试。
    private let runtimeSessionManager: WatchTrainingRuntimeSessionManaging

    var buttonTitle: String {
        switch state {
        case .notTraining:
            "长按开始"
        case .training:
            "双击/旋钮打点\n长按结束"
        }
    }

    var buttonColor: Color {
        switch state {
        case .notTraining:
            .green
        case .training:
            .red
        }
    }

    var markerCount: Int {
        state == .training ? markers.count : 0
    }

    var markerCountText: String {
        "打点数: \(markerCount)"
    }

    init(
        now: @escaping () -> Date = Date.init,
        idFactory: @escaping () -> UUID = UUID.init,
        runtimeSessionManager: WatchTrainingRuntimeSessionManaging? = nil,
    ) {
        self.now = now
        self.idFactory = idFactory

        // ViewModel 的默认值保持 no-op，避免单元测试、预览和纯状态验证时触发 HealthKit 授权。
        // 真正的 app 入口在 WatchTrainingView 初始化时会注入 HealthKitWorkoutRuntimeSessionManager。
        self.runtimeSessionManager = runtimeSessionManager ?? NoOpWatchTrainingRuntimeSessionManager()
    }

    @discardableResult
    func handleLongPress() -> TrainingSessionSyncPayload? {
        switch state {
        case .notTraining:
            // 开始训练时先记录统一的 startedAt，再用同一个时间启动系统 workout session。
            // 这样本地训练 payload 和 HealthKit workout 的开始时间保持一致。
            let startedAt = now()
            self.startedAt = startedAt
            endedAt = nil
            markers = []
            state = .training
            runtimeSessionManager.startTraining(at: startedAt)
            return nil
        case .training:
            // 结束训练时同理只取一次 completedAt，让 payload 的 endedAt 和系统 session
            // 的结束时间对齐，避免 UI 状态、同步数据和 HealthKit 记录出现几秒级偏差。
            let completedAt = now()
            endedAt = completedAt
            state = .notTraining
            runtimeSessionManager.endTraining(at: completedAt)
            return TrainingSessionSyncPayload(
                id: idFactory(),
                startedAt: startedAt ?? completedAt,
                endedAt: completedAt,
                events: markers.map {
                    ShotMarkerEventSyncPayload(id: idFactory(), markedAt: $0)
                },
            )
        }
    }

    @discardableResult
    func handleLongPress(syncService: WatchTrainingSyncServiceProtocol) -> TrainingSessionSyncPayload? {
        guard let payload = handleLongPress() else {
            return nil
        }

        try? syncService.enqueueCompletedSession(payload)
        return payload
    }

    @discardableResult
    func handleDoubleTap() -> Bool {
        guard state == .training else {
            return false
        }

        markers.append(now())
        return true
    }
}
