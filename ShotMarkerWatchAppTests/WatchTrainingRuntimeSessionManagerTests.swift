@testable import ShotMarkerWatchApp
import XCTest

@MainActor
final class WatchTrainingRuntimeSessionManagerTests: XCTestCase {
    func testAuthorizationAfterTrainingEndedDoesNotStartWorkout() {
        let backend = ControlledWorkoutBackend()
        let manager = HealthKitWorkoutRuntimeSessionManager(backend: backend)

        manager.startTraining(at: Date(timeIntervalSince1970: 100))
        manager.endTraining(at: Date(timeIntervalSince1970: 200))
        backend.completeAuthorization(at: 0, authorized: true)

        XCTAssertTrue(backend.workouts.isEmpty)
    }

    func testDeniedAuthorizationAllowsLaterTrainingToStart() {
        let backend = ControlledWorkoutBackend()
        let manager = HealthKitWorkoutRuntimeSessionManager(backend: backend)

        manager.startTraining(at: Date(timeIntervalSince1970: 100))
        backend.completeAuthorization(at: 0, authorized: false)
        manager.endTraining(at: Date(timeIntervalSince1970: 200))
        manager.startTraining(at: Date(timeIntervalSince1970: 300))
        backend.completeAuthorization(at: 1, authorized: true)

        XCTAssertEqual(backend.workouts.count, 1)
        XCTAssertEqual(backend.workouts.first?.startedAt, [Date(timeIntervalSince1970: 300)])
    }

    func testDuplicateStartWhileAuthorizingDoesNotRequestAgain() {
        let backend = ControlledWorkoutBackend()
        let manager = HealthKitWorkoutRuntimeSessionManager(backend: backend)

        manager.startTraining(at: Date(timeIntervalSince1970: 100))
        manager.startTraining(at: Date(timeIntervalSince1970: 150))
        backend.completeAuthorization(at: 0, authorized: true)

        XCTAssertEqual(backend.authorizationCompletions.count, 1)
        XCTAssertEqual(backend.workouts.first?.startedAt, [Date(timeIntervalSince1970: 100)])
    }

    func testRepeatedEndFinishesWorkoutOnlyOnce() throws {
        let backend = ControlledWorkoutBackend()
        let manager = HealthKitWorkoutRuntimeSessionManager(backend: backend)
        manager.startTraining(at: Date(timeIntervalSince1970: 100))
        backend.completeAuthorization(at: 0, authorized: true)
        let workout = try XCTUnwrap(backend.workouts.first)

        manager.endTraining(at: Date(timeIntervalSince1970: 200))
        manager.endTraining(at: Date(timeIntervalSince1970: 250))

        XCTAssertEqual(workout.endedAt, [Date(timeIntervalSince1970: 200)])
    }

    func testNewTrainingWaitsForPreviousWorkoutToFinishThenStartsAtOriginalDate() throws {
        let backend = ControlledWorkoutBackend()
        let manager = HealthKitWorkoutRuntimeSessionManager(backend: backend)
        manager.startTraining(at: Date(timeIntervalSince1970: 100))
        backend.completeAuthorization(at: 0, authorized: true)
        let oldWorkout = try XCTUnwrap(backend.workouts.first)

        manager.endTraining(at: Date(timeIntervalSince1970: 200))
        manager.startTraining(at: Date(timeIntervalSince1970: 300))
        XCTAssertEqual(backend.workouts.count, 1)
        oldWorkout.completeEnd()
        XCTAssertEqual(backend.authorizationCompletions.count, 2)
        backend.completeAuthorization(at: 1, authorized: true)

        XCTAssertEqual(backend.workouts.count, 2)
        XCTAssertEqual(backend.workouts.last?.startedAt, [Date(timeIntervalSince1970: 300)])
        XCTAssertTrue(backend.workouts.last?.endedAt.isEmpty == true)
    }

    func testQueuedTrainingEndedBeforePreviousWorkoutFinishesIsNeverStarted() throws {
        let backend = ControlledWorkoutBackend()
        let manager = HealthKitWorkoutRuntimeSessionManager(backend: backend)
        manager.startTraining(at: Date(timeIntervalSince1970: 100))
        backend.completeAuthorization(at: 0, authorized: true)
        let oldWorkout = try XCTUnwrap(backend.workouts.first)
        manager.endTraining(at: Date(timeIntervalSince1970: 200))

        manager.startTraining(at: Date(timeIntervalSince1970: 300))
        manager.endTraining(at: Date(timeIntervalSince1970: 400))
        oldWorkout.completeEnd()

        XCTAssertEqual(backend.workouts.count, 1)
        XCTAssertEqual(backend.authorizationCompletions.count, 1)
        XCTAssertEqual(oldWorkout.endedAt, [Date(timeIntervalSince1970: 200)])
    }

    func testOldAuthorizationCannotStartReplacementTrainingWithOldDate() {
        let backend = ControlledWorkoutBackend()
        let manager = HealthKitWorkoutRuntimeSessionManager(backend: backend)
        manager.startTraining(at: Date(timeIntervalSince1970: 100))
        manager.endTraining(at: Date(timeIntervalSince1970: 200))
        manager.startTraining(at: Date(timeIntervalSince1970: 300))

        backend.completeAuthorization(at: 0, authorized: true)
        XCTAssertTrue(backend.workouts.isEmpty)
        backend.completeAuthorization(at: 1, authorized: true)

        XCTAssertEqual(backend.workouts.count, 1)
        XCTAssertEqual(backend.workouts.first?.startedAt, [Date(timeIntervalSince1970: 300)])
    }

    func testReversedAuthorizationCallbacksPreserveNewestTraining() {
        let backend = ControlledWorkoutBackend()
        let manager = HealthKitWorkoutRuntimeSessionManager(backend: backend)
        manager.startTraining(at: Date(timeIntervalSince1970: 100))
        manager.endTraining(at: Date(timeIntervalSince1970: 200))
        manager.startTraining(at: Date(timeIntervalSince1970: 300))

        backend.completeAuthorization(at: 1, authorized: true)
        backend.completeAuthorization(at: 0, authorized: false)
        manager.endTraining(at: Date(timeIntervalSince1970: 400))

        XCTAssertEqual(backend.workouts.count, 1)
        XCTAssertEqual(backend.workouts.first?.startedAt, [Date(timeIntervalSince1970: 300)])
        XCTAssertEqual(backend.workouts.first?.endedAt, [Date(timeIntervalSince1970: 400)])
    }

    func testLatePreviousWorkoutCompletionCannotClearNewWorkout() throws {
        let backend = ControlledWorkoutBackend()
        let manager = HealthKitWorkoutRuntimeSessionManager(backend: backend)
        manager.startTraining(at: Date(timeIntervalSince1970: 100))
        backend.completeAuthorization(at: 0, authorized: true)
        let oldWorkout = try XCTUnwrap(backend.workouts.first)
        manager.endTraining(at: Date(timeIntervalSince1970: 200))
        oldWorkout.completeEnd()
        manager.startTraining(at: Date(timeIntervalSince1970: 300))
        backend.completeAuthorization(at: 1, authorized: true)
        let newWorkout = try XCTUnwrap(backend.workouts.last)

        oldWorkout.completeEnd()
        manager.endTraining(at: Date(timeIntervalSince1970: 400))

        XCTAssertEqual(backend.workouts.count, 2)
        XCTAssertEqual(newWorkout.endedAt, [Date(timeIntervalSince1970: 400)])
        XCTAssertEqual(oldWorkout.endedAt, [Date(timeIntervalSince1970: 200)])
    }
}

// Only the external HealthKit boundary is replaced: the real manager must decide
// which authorization and persistence callback belongs to the current training.
@MainActor
private final class ControlledWorkoutBackend: WatchWorkoutRuntimeBackend {
    var isAvailable = true
    private(set) var authorizationCompletions: [@MainActor (Bool) -> Void] = []
    private(set) var workouts: [ControlledWorkout] = []

    func requestAuthorization(completion: @escaping @MainActor (Bool) -> Void) {
        authorizationCompletions.append(completion)
    }

    func completeAuthorization(at index: Int, authorized: Bool) {
        guard authorizationCompletions.indices.contains(index) else {
            XCTFail("Expected pending authorization at index \(index)")
            return
        }
        authorizationCompletions[index](authorized)
    }

    func makeWorkout() throws -> any WatchWorkoutRuntimeHandle {
        let workout = ControlledWorkout()
        workouts.append(workout)
        return workout
    }
}

@MainActor
private final class ControlledWorkout: WatchWorkoutRuntimeHandle {
    private(set) var startedAt: [Date] = []
    private(set) var endedAt: [Date] = []
    private var endCompletion: (@MainActor () -> Void)?

    func start(at date: Date) {
        startedAt.append(date)
    }

    func end(at date: Date, completion: @escaping @MainActor () -> Void) {
        endedAt.append(date)
        endCompletion = completion
    }

    func completeEnd() {
        endCompletion?()
    }
}
