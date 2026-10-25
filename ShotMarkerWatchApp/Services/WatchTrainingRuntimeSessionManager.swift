import Foundation

#if canImport(HealthKit)
    import HealthKit
#endif

@MainActor
protocol WatchTrainingRuntimeSessionManaging: AnyObject {
    func startTraining(at startDate: Date)
    func endTraining(at endDate: Date)
}

@MainActor
final class NoOpWatchTrainingRuntimeSessionManager: WatchTrainingRuntimeSessionManaging {
    func startTraining(at startDate: Date) {}
    func endTraining(at endDate: Date) {}
}

// Keep system authorization and workout persistence outside the training coordinator,
// so their callbacks can be controlled without a real HealthKit permission prompt.
@MainActor
protocol WatchWorkoutRuntimeBackend: AnyObject {
    var isAvailable: Bool { get }
    func requestAuthorization(completion: @escaping @MainActor (Bool) -> Void)
    func makeWorkout() throws -> any WatchWorkoutRuntimeHandle
}

@MainActor
protocol WatchWorkoutRuntimeHandle: AnyObject {
    func start(at date: Date)
    func end(at date: Date, completion: @escaping @MainActor () -> Void)
}

@MainActor
final class HealthKitWorkoutRuntimeSessionManager: WatchTrainingRuntimeSessionManaging {
    private struct TrainingRequest {
        let id = UUID()
        let startedAt: Date
    }

    private enum State {
        case idle
        case authorizing(UUID)
        case running(UUID, any WatchWorkoutRuntimeHandle)
        case finishing(UUID, any WatchWorkoutRuntimeHandle)
    }

    private let backend: any WatchWorkoutRuntimeBackend
    private var state = State.idle
    // A new training can wait here while the previous workout is still saving.
    private var desiredTraining: TrainingRequest?

    init(backend: any WatchWorkoutRuntimeBackend) {
        self.backend = backend
    }

    #if canImport(HealthKit)
        convenience init(healthStore: HKHealthStore = HKHealthStore()) {
            self.init(backend: HealthKitWorkoutRuntimeBackend(healthStore: healthStore))
        }
    #else
        convenience init() {
            self.init(backend: UnavailableWorkoutRuntimeBackend())
        }
    #endif

    func startTraining(at startDate: Date) {
        guard backend.isAvailable, desiredTraining == nil else { return }
        desiredTraining = TrainingRequest(startedAt: startDate)
        startDesiredTrainingIfIdle()
    }

    func endTraining(at endDate: Date) {
        // Invalidate authorization or queued work before handling the system session.
        desiredTraining = nil
        switch state {
        case .idle, .authorizing:
            state = .idle
        case let .running(id, workout):
            state = .finishing(id, workout)
            workout.end(at: endDate) { [weak self] in
                guard let self, case let .finishing(finishingID, _) = self.state,
                      finishingID == id
                else { return }
                self.state = .idle
                self.startDesiredTrainingIfIdle()
            }
        case .finishing:
            break
        }
    }

    private func startDesiredTrainingIfIdle() {
        guard case .idle = state, let request = desiredTraining else { return }
        state = .authorizing(request.id)
        backend.requestAuthorization { [weak self] authorized in
            self?.completeAuthorization(authorized, for: request)
        }
    }

    private func completeAuthorization(_ authorized: Bool, for request: TrainingRequest) {
        guard case let .authorizing(id) = state, id == request.id,
              desiredTraining?.id == request.id
        else { return }
        guard authorized, let workout = try? backend.makeWorkout() else {
            desiredTraining = nil
            state = .idle
            return
        }
        state = .running(request.id, workout)
        workout.start(at: request.startedAt)
    }
}

#if canImport(HealthKit)
    @MainActor
    private final class HealthKitWorkoutRuntimeBackend: WatchWorkoutRuntimeBackend {
        let healthStore: HKHealthStore
        var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

        init(healthStore: HKHealthStore) {
            self.healthStore = healthStore
        }

        func requestAuthorization(completion: @escaping @MainActor (Bool) -> Void) {
            // Only write workouts; ShotMarker does not read heart rate or other health data.
            healthStore.requestAuthorization(toShare: [HKObjectType.workoutType()], read: []) { authorized, _ in
                Task { @MainActor in completion(authorized) }
            }
        }

        func makeWorkout() throws -> any WatchWorkoutRuntimeHandle {
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .other
            configuration.locationType = .unknown
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration,
            )
            return HealthKitWorkoutRuntimeHandle(session: session, builder: builder)
        }
    }

    @MainActor
    private final class HealthKitWorkoutRuntimeHandle: WatchWorkoutRuntimeHandle {
        private let session: HKWorkoutSession
        private let builder: HKLiveWorkoutBuilder

        init(session: HKWorkoutSession, builder: HKLiveWorkoutBuilder) {
            self.session = session
            self.builder = builder
        }

        func start(at date: Date) {
            session.startActivity(with: date)
            builder.beginCollection(withStart: date) { _, _ in }
        }

        func end(at date: Date, completion: @escaping @MainActor () -> Void) {
            session.stopActivity(with: date)
            session.end()
            // Keep this exact session/builder alive through both asynchronous steps.
            // A persistence failure must also release the coordinator's finishing slot.
            Task { @MainActor [self] in
                defer { completion() }
                _ = try? await builder.endCollection(at: date)
                _ = try? await builder.finishWorkout()
            }
        }
    }
#else
    @MainActor
    private final class UnavailableWorkoutRuntimeBackend: WatchWorkoutRuntimeBackend {
        var isAvailable: Bool { false }
        func requestAuthorization(completion: @escaping @MainActor (Bool) -> Void) {}
        func makeWorkout() throws -> any WatchWorkoutRuntimeHandle {
            throw CocoaError(.featureUnsupported)
        }
    }
#endif
