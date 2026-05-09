import Foundation

#if canImport(HealthKit)
    import HealthKit
#endif

// ViewModel 只需要知道“训练开始/结束时要通知系统运行会话”，不应该直接依赖
// HealthKit 的授权、HKWorkoutSession 创建、workout builder 生命周期等平台细节。
// 这个协议把业务状态机和 watchOS runtime 保活机制隔开，单测可以注入 spy，
// 真机运行时则由 HealthKitWorkoutRuntimeSessionManager 执行系统级 workout session。
@MainActor
protocol WatchTrainingRuntimeSessionManaging: AnyObject {
    func startTraining(at startDate: Date)
    func endTraining(at endDate: Date)
}

// 默认 no-op 实现用于单元测试和 SwiftUI 预览一类“不应该弹 HealthKit 授权”的场景。
// WatchTrainingView 会显式注入真正的 HealthKit 实现，所以生产路径不会停在这里。
@MainActor
final class NoOpWatchTrainingRuntimeSessionManager: WatchTrainingRuntimeSessionManaging {
    func startTraining(at startDate: Date) {}
    func endTraining(at endDate: Date) {}
}

// Apple Watch 上普通 app 在放下手腕后会被系统按常规前台 app 处理，屏幕会熄灭，
// 用户再次抬腕也不一定回到我们的训练界面。启动 HKWorkoutSession 后，系统会把
// 这段时间识别为 workout app 的 active session：app 可以继续在后台运行，
// 抬腕时也会优先回到当前训练 app。这是修复“训练中熄屏后要重新进 app”的关键。
@MainActor
final class HealthKitWorkoutRuntimeSessionManager: WatchTrainingRuntimeSessionManaging {
    #if canImport(HealthKit)
        private let healthStore: HKHealthStore

        // 必须强引用 session 和 builder。HKWorkoutSession 一旦被释放，
        // 系统就没有正在进行的 workout runtime 可维护，后台运行能力也会消失。
        private var workoutSession: HKWorkoutSession?
        private var workoutBuilder: HKLiveWorkoutBuilder?

        init(healthStore: HKHealthStore = HKHealthStore()) {
            self.healthStore = healthStore
        }

        func startTraining(at startDate: Date) {
            // HealthKit 在部分环境不可用，例如某些模拟器/受限设备；已有 session 时也不重复启动，
            // 避免一次训练被重复创建多个 HKWorkoutSession。
            guard HKHealthStore.isHealthDataAvailable(), workoutSession == nil else {
                return
            }

            // 我们只需要写入 workout，让系统把本次训练识别为 workout session。
            // 当前功能不读取心率、步数等 Health 数据，所以 read 保持为空，权限范围更窄。
            let workoutType = HKObjectType.workoutType()
            healthStore.requestAuthorization(toShare: Set([workoutType]), read: []) { [weak self] isAuthorized, _ in
                guard isAuthorized else {
                    return
                }

                // HealthKit 授权回调是并发执行闭包，不能直接读写这个 @MainActor 类型上的状态。
                // 这里用 Task 的 capture list 重新弱捕获 self，再切回 MainActor 调用实例方法。
                // 这样 Swift 不会把外层闭包里的 weak self 变量跨并发边界传递，也不会在 Swift 6
                // 语言模式下触发“captured var self”的错误。
                Task { @MainActor [weak self] in
                    self?.startAuthorizedWorkout(at: startDate)
                }
            }
        }

        func endTraining(at endDate: Date) {
            // 没有 active session 时直接返回。这个情况可能来自用户拒绝 HealthKit 权限、
            // HealthKit 不可用，或训练状态被恢复/重入时没有对应的系统 session。
            guard let workoutSession else {
                return
            }

            // stopActivity 结束 workout 的活动时间，end 通知 session 生命周期结束。
            // builder 负责把 workout collection 关闭并写入 HealthKit。
            workoutSession.stopActivity(with: endDate)
            workoutSession.end()
            workoutBuilder?.endCollection(withEnd: endDate) { [weak self] _, _ in
                // endCollection 的完成回调同样不在 MainActor 上。不能在这个 @Sendable 回调里
                // 直接访问 self.workoutBuilder，否则就是从并发闭包访问 MainActor 隔离属性。
                // 所以这里只负责把“collection 已结束”的事件转回 MainActor，由
                // finishWorkoutOnMainActor() 在 actor 隔离范围内读取 builder 并继续 finish。
                Task { @MainActor [weak self] in
                    self?.finishWorkoutOnMainActor()
                }
            }
        }

        private func startAuthorizedWorkout(at startDate: Date) {
            // 授权是异步的，用户可能在授权弹窗期间结束训练或重复触发开始。
            // 这里再次检查，确保最终只保留一个 runtime session。
            guard workoutSession == nil else {
                return
            }

            // ShotMarker 目前只需要让系统知道“用户正在训练”，不做运动类型统计。
            // .other + .unknown 是最保守的配置，避免误报跑步、骑行等具体运动。
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .other
            configuration.locationType = .unknown

            // 创建失败时保持静默降级：训练 UI 和打点仍然可用，只是无法获得系统 workout
            // runtime 的后台/抬腕回前台能力。这里不抛给 UI，是为了不阻塞核心打点流程。
            guard let workoutSession = try? HKWorkoutSession(
                healthStore: healthStore,
                configuration: configuration,
            ) else {
                return
            }

            // associatedWorkoutBuilder 会收集并最终写入 workout。即便我们不展示实时 Health
            // 指标，builder 仍是完整结束/保存 workout 的标准路径。
            let workoutBuilder = workoutSession.associatedWorkoutBuilder()
            workoutBuilder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration,
            )

            // 先保存强引用，再 startActivity，确保系统 session 启动后不会立刻被释放。
            self.workoutSession = workoutSession
            self.workoutBuilder = workoutBuilder

            workoutSession.startActivity(with: startDate)
            workoutBuilder.beginCollection(withStart: startDate) { _, _ in }
        }

        private func finishWorkoutOnMainActor() {
            // 这个方法只会在 MainActor 上运行，因此可以安全读取 workoutBuilder。
            // finishWorkout 本身仍然是 HealthKit 异步回调；完成后还要再次切回 MainActor，
            // 再清空 workoutSession/workoutBuilder 两个 actor 隔离状态。
            workoutBuilder?.finishWorkout { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.clearWorkout()
                }
            }
        }

        private func clearWorkout() {
            // finishWorkout 完成后释放引用。下一次长按开始训练时可以创建新的系统 workout session。
            workoutSession = nil
            workoutBuilder = nil
        }
    #else
        // 非 watchOS/不可导入 HealthKit 的编译环境保留空实现，保证共享测试或预览构建不被平台 API 卡住。
        func startTraining(at startDate: Date) {}
        func endTraining(at endDate: Date) {}
    #endif
}
