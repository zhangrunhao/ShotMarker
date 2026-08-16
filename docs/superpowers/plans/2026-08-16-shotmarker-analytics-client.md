# ShotMarker Analytics Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the smallest first-party analytics client to ShotMarker so iPhone Release builds report four fixed success events with a random per-installation identifier, while Debug, tests, iPad, and Apple Watch remain no-op.

**Architecture:** A dedicated `AnalyticsTracking` boundary separates product analytics from `AppLogger` and GlitchTip. `InstallationIDStore` owns one 12-character UserDefaults identifier. `AnalyticsClient` constructs one fixed HTTPS GET request and schedules it without retry or business-flow coupling. Existing services receive the tracker through initializer injection, and the app composition root selects live versus no-op behavior.

**Tech Stack:** Swift 5 language mode, SwiftUI, Foundation `URLSession`, XCTest, Xcode 26.5, iOS 26.4+.

---

## Scope and repository boundary

This plan implements the iPhone half of:

```text
/Users/runhaozhang/Documents/project/ShotMarker/docs/superpowers/specs/2026-08-16-shotmarker-analytics-design.md
```

All commands run in:

```text
/Users/runhaozhang/Documents/project/ShotMarker
```

The plan intentionally does not:

- reuse `AppLogger` or add analytics fields to local/GlitchTip logs;
- send training IDs, timestamps, video data, job IDs, errors, device model, or OS version;
- add an outbox, retry, batch, response callback, settings toggle, or ATT prompt;
- add networking to the Watch target;
- alter GlitchTip initialization, reporting, package references, or tests;
- update App Store Connect automatically.

The Xcode project uses filesystem-synchronized groups. New Swift, test, and privacy-manifest files should be discovered without hand-editing `project.pbxproj`; verify that behavior before touching the project file.

## File map

- Create: `ShotMarker/Services/Analytics/AnalyticsEvent.swift`
- Create: `ShotMarker/Services/Analytics/InstallationIDStore.swift`
- Create: `ShotMarker/Services/Analytics/AnalyticsClient.swift`
- Create: `ShotMarker/Services/Analytics/AnalyticsRuntimePolicy.swift`
- Create or merge: `ShotMarker/PrivacyInfo.xcprivacy`
- Modify: `ShotMarker/Services/PhoneWatchSyncService.swift`
- Modify: `ShotMarker/ViewModels/HighlightJobManager.swift`
- Modify: `ShotMarker/ShotMarkerApp.swift`
- Create: `ShotMarkerTests/AnalyticsEventTests.swift`
- Create: `ShotMarkerTests/InstallationIDStoreTests.swift`
- Create: `ShotMarkerTests/AnalyticsClientTests.swift`
- Create: `ShotMarkerTests/AnalyticsRuntimePolicyTests.swift`
- Create: `ShotMarkerTests/SpyAnalyticsTracker.swift`
- Create: `ShotMarkerTests/PrivacyManifestTests.swift`
- Modify: `ShotMarkerTests/PhoneWatchSyncServiceTests.swift`
- Modify: `ShotMarkerTests/HighlightJobManagerTests.swift`

### Task 0: Protect the in-progress GlitchTip work

- [ ] **Step 1: Confirm the repository and branch**

Run:

```bash
pwd
git branch --show-current
git status --short
```

Expected:

- `pwd` is `/Users/runhaozhang/Documents/project/ShotMarker`;
- the branch is `main`;
- the worktree is clean before analytics implementation begins.

The known GlitchTip edits in `project.pbxproj`, `AppLogger.swift`, `ShotMarkerApp.swift`, tests, and the new crash-reporter files must be completed and committed first. Do not stash, discard, or overwrite them.

- [ ] **Step 2: Verify the GlitchTip composition baseline**

Run:

```bash
rg -n "GlitchTipCrashReporter.start|GlitchTipErrorReporter" \
  ShotMarker/ShotMarkerApp.swift \
  ShotMarker/Services/AppLogging
```

Expected: the finalized crash-reporting composition is visible. Analytics changes must be additive around this code.

- [ ] **Step 3: Verify the test destination**

Run:

```bash
xcrun simctl list devices available | rg "iPhone 17 Pro.*26.5|-- iOS 26.5 --"
```

Expected: an iPhone 17 Pro simulator exists for iOS 26.5. If that runtime is unavailable when executing the plan, select another listed iPhone runtime at or above the 26.4 deployment target and use the same destination consistently.

### Task 1: Define fixed events and the per-installation identifier

**Files:**

- Create: `ShotMarkerTests/AnalyticsEventTests.swift`
- Create: `ShotMarkerTests/InstallationIDStoreTests.swift`
- Create: `ShotMarker/Services/Analytics/AnalyticsEvent.swift`
- Create: `ShotMarker/Services/Analytics/InstallationIDStore.swift`

- [ ] **Step 1: Add the failing fixed-event test**

Create `ShotMarkerTests/AnalyticsEventTests.swift`:

```swift
@testable import ShotMarker
import Foundation
import XCTest

final class AnalyticsEventTests: XCTestCase {
    func testEventRawValuesAreTheApprovedFourEventContract() {
        XCTAssertEqual(
            AnalyticsEvent.allCases.map(\.rawValue),
            [
                "app_launch",
                "training_sync_succeeded",
                "highlight_generate_succeeded",
                "highlight_save_succeeded",
            ],
        )
    }
}
```

- [ ] **Step 2: Add the failing installation-ID tests**

Create `ShotMarkerTests/InstallationIDStoreTests.swift`:

```swift
@testable import ShotMarker
import Foundation
import XCTest

final class InstallationIDStoreTests: XCTestCase {
    private var suiteName: String!
    private var userDefaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "ShotMarker.InstallationIDStoreTests.\(UUID().uuidString)"
        userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        suiteName = nil
    }

    func testFirstReadGeneratesAndPersistsTwelveCharacterIdentifier() {
        let store = InstallationIDStore(
            userDefaults: userDefaults,
            makeID: { "AbCd1234Ef56" },
        )

        XCTAssertEqual(store.installationID(), "AbCd1234Ef56")
        XCTAssertEqual(
            userDefaults.string(forKey: InstallationIDStore.storageKey),
            "AbCd1234Ef56",
        )
    }

    func testLaterStoreInstancesReuseThePersistedIdentifier() {
        userDefaults.set("Reuse1234AbC", forKey: InstallationIDStore.storageKey)
        let store = InstallationIDStore(
            userDefaults: userDefaults,
            makeID: { "Other1234AbC" },
        )

        XCTAssertEqual(store.installationID(), "Reuse1234AbC")
    }

    func testMalformedStoredValueIsReplaced() {
        userDefaults.set("not-valid", forKey: InstallationIDStore.storageKey)
        let store = InstallationIDStore(
            userDefaults: userDefaults,
            makeID: { "Valid1234AbC" },
        )

        XCTAssertEqual(store.installationID(), "Valid1234AbC")
        XCTAssertEqual(
            userDefaults.string(forKey: InstallationIDStore.storageKey),
            "Valid1234AbC",
        )
    }

    func testDefaultGeneratorProducesTwelveAlphanumericCharacters() {
        let value = InstallationIDStore(userDefaults: userDefaults).installationID()

        XCTAssertTrue(InstallationIDStore.isValid(value))
        XCTAssertEqual(value.utf8.count, 12)
    }
}
```

- [ ] **Step 3: Run the new tests and verify RED**

Run:

```bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/AnalyticsEventTests \
  -only-testing:ShotMarkerTests/InstallationIDStoreTests
```

Expected: compilation fails because `AnalyticsEvent` and `InstallationIDStore` do not exist.

- [ ] **Step 4: Implement the closed event and tracking boundary**

Create `ShotMarker/Services/Analytics/AnalyticsEvent.swift`:

```swift
import Foundation

nonisolated enum AnalyticsEvent: String, CaseIterable, Sendable {
    case appLaunch = "app_launch"
    case trainingSyncSucceeded = "training_sync_succeeded"
    case highlightGenerateSucceeded = "highlight_generate_succeeded"
    case highlightSaveSucceeded = "highlight_save_succeeded"
}

nonisolated protocol AnalyticsTracking: Sendable {
    func track(_ event: AnalyticsEvent)
}

nonisolated struct NoopAnalyticsTracker: AnalyticsTracking {
    func track(_ event: AnalyticsEvent) {}
}
```

The protocol accepts no custom parameter dictionary. Adding an event therefore requires changing this enum and its contract test.

- [ ] **Step 5: Implement the UserDefaults installation store**

Create `ShotMarker/Services/Analytics/InstallationIDStore.swift`:

```swift
import Foundation

nonisolated protocol InstallationIDProviding: Sendable {
    func installationID() -> String
}

nonisolated final class InstallationIDStore: InstallationIDProviding, @unchecked Sendable {
    static let shared = InstallationIDStore()
    static let storageKey = "analytics.installation_id"

    private let userDefaults: UserDefaults
    private let makeID: @Sendable () -> String
    private let lock = NSLock()

    init(
        userDefaults: UserDefaults = .standard,
        makeID: @Sendable @escaping () -> String = InstallationIDStore.makeRandomID,
    ) {
        self.userDefaults = userDefaults
        self.makeID = makeID
    }

    func installationID() -> String {
        lock.withLock {
            if let stored = userDefaults.string(forKey: Self.storageKey),
               Self.isValid(stored)
            {
                return stored
            }

            let generated = makeID()
            precondition(Self.isValid(generated), "Installation ID generator must return 12 alphanumeric characters")
            userDefaults.set(generated, forKey: Self.storageKey)
            return generated
        }
    }

    static func isValid(_ value: String) -> Bool {
        guard value.utf8.count == 12 else {
            return false
        }

        return value.utf8.allSatisfy { byte in
            (48 ... 57).contains(byte)
                || (65 ... 90).contains(byte)
                || (97 ... 122).contains(byte)
        }
    }

    static func makeRandomID() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12))
    }
}
```

Do not use IDFA, IDFV, Keychain, device name, IP address, or iCloud. UserDefaults deletion during uninstall is the intended identity boundary.

- [ ] **Step 6: Run the focused tests and verify GREEN**

Run the command from Step 3 again.

Expected: both new test classes pass and no network request is made.

- [ ] **Step 7: Commit the event and identifier layer**

Run:

```bash
git add \
  ShotMarker/Services/Analytics/AnalyticsEvent.swift \
  ShotMarker/Services/Analytics/InstallationIDStore.swift \
  ShotMarkerTests/AnalyticsEventTests.swift \
  ShotMarkerTests/InstallationIDStoreTests.swift
git diff --cached --check
git commit -m "feat: 添加埋点事件与安装标识"
```

Expected: one commit containing only the closed event contract and installation identifier.

### Task 2: Build the fire-and-forget HTTPS client

**Files:**

- Create: `ShotMarkerTests/AnalyticsClientTests.swift`
- Create: `ShotMarker/Services/Analytics/AnalyticsClient.swift`

- [ ] **Step 1: Add the failing request-construction tests**

Create `ShotMarkerTests/AnalyticsClientTests.swift`:

```swift
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
        let components = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
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
```

- [ ] **Step 2: Run the client tests and verify RED**

Run:

```bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/AnalyticsClientTests
```

Expected: compilation fails because `AnalyticsClient` does not exist.

- [ ] **Step 3: Implement the client**

Create `ShotMarker/Services/Analytics/AnalyticsClient.swift`:

```swift
import Foundation

nonisolated final class AnalyticsClient: AnalyticsTracking, @unchecked Sendable {
    typealias RequestSender = @Sendable (URLRequest) async -> Void

    static let productionEndpoint = URL(string: "https://zhangrh.shop/track")!

    private let endpoint: URL
    private let installationIDProvider: InstallationIDProviding
    private let now: @Sendable () -> Date
    private let sendRequest: RequestSender

    init(
        endpoint: URL = AnalyticsClient.productionEndpoint,
        installationIDProvider: InstallationIDProviding = InstallationIDStore.shared,
        now: @Sendable @escaping () -> Date = Date.init,
        sendRequest: @escaping RequestSender,
    ) {
        self.endpoint = endpoint
        self.installationIDProvider = installationIDProvider
        self.now = now
        self.sendRequest = sendRequest
    }

    func track(_ event: AnalyticsEvent) {
        guard let request = makeRequest(for: event) else {
            return
        }

        let sendRequest = sendRequest
        Task {
            await sendRequest(request)
        }
    }

    func makeRequest(for event: AnalyticsEvent) -> URLRequest? {
        guard var components = URLComponents(
            url: endpoint,
            resolvingAgainstBaseURL: false,
        ) else {
            return nil
        }

        let milliseconds = Int64((now().timeIntervalSince1970 * 1_000).rounded(.down))
        components.queryItems = [
            URLQueryItem(name: "time", value: String(milliseconds)),
            URLQueryItem(name: "project", value: "shotmarker"),
            URLQueryItem(name: "device_id", value: installationIDProvider.installationID()),
            URLQueryItem(name: "event", value: event.rawValue),
            URLQueryItem(name: "params", value: "{}"),
        ]

        guard let url = components.url else {
            return nil
        }

        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 5,
        )
        request.httpMethod = "GET"
        return request
    }

    static func live(
        installationIDProvider: InstallationIDProviding = InstallationIDStore.shared,
    ) -> AnalyticsClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)

        return AnalyticsClient(
            installationIDProvider: installationIDProvider,
            sendRequest: { request in
                do {
                    let (_, response) = try await session.data(for: request)
                    guard let response = response as? HTTPURLResponse,
                          response.statusCode == 204
                    else {
                        return
                    }
                } catch {
                    return
                }
            },
        )
    }
}
```

The sender swallows transport errors and non-204 responses. It does not call business code, log remotely, persist requests, or schedule retries.

- [ ] **Step 4: Run the client tests and verify GREEN**

Run the command from Step 2 again.

Expected: both request construction and one-attempt behavior pass.

- [ ] **Step 5: Commit the transport layer**

Run:

```bash
git add \
  ShotMarker/Services/Analytics/AnalyticsClient.swift \
  ShotMarkerTests/AnalyticsClientTests.swift
git diff --cached --check
git commit -m "feat: 添加最小埋点发送客户端"
```

Expected: one commit containing the fire-and-forget client and its tests.

### Task 3: Report successful Watch training imports

**Files:**

- Create: `ShotMarkerTests/SpyAnalyticsTracker.swift`
- Modify: `ShotMarkerTests/PhoneWatchSyncServiceTests.swift`
- Modify: `ShotMarker/Services/PhoneWatchSyncService.swift`

- [ ] **Step 1: Add a thread-safe reusable analytics spy**

Create `ShotMarkerTests/SpyAnalyticsTracker.swift`:

```swift
@testable import ShotMarker
import Foundation

nonisolated final class SpyAnalyticsTracker: AnalyticsTracking, @unchecked Sendable {
    private let lock = NSLock()
    private var storedEvents: [AnalyticsEvent] = []

    var events: [AnalyticsEvent] {
        lock.withLock {
            storedEvents
        }
    }

    func track(_ event: AnalyticsEvent) {
        lock.withLock {
            storedEvents.append(event)
        }
    }
}
```

- [ ] **Step 2: Add failing sync-event assertions**

In `testCompletedTrainingSessionUserInfoImportsPostsNotificationAndTransfersAck`, create `let analytics = SpyAnalyticsTracker()`, inject `analytics: analytics`, and add:

```swift
        XCTAssertEqual(analytics.events, [.trainingSyncSucceeded])
```

In `testDuplicateCompletedTrainingSessionUserInfoImportsAndAcksEachArrival`, inject the spy and assert the documented at-least-once behavior:

```swift
        XCTAssertEqual(
            analytics.events,
            [.trainingSyncSucceeded, .trainingSyncSucceeded],
        )
```

In `testImportFailureDoesNotPostNotificationOrAck`, inject the spy and add:

```swift
        XCTAssertTrue(analytics.events.isEmpty)
```

Add a dedicated test proving ACK failure does not retract a successful import event:

```swift
    func testSuccessfulImportTracksEvenWhenAckTransferFails() throws {
        let payload = try makePayload()
        let analytics = SpyAnalyticsTracker()
        let session = FakePhoneWatchConnectivitySession(isSupported: true)
        session.transferUserInfoError = SyncAckError.failed
        let service = PhoneWatchSyncService(
            importer: SpyTrainingSessionImporter(),
            session: session,
            analytics: analytics,
        )

        service.handleReceivedUserInfo(
            try makeCompletedTrainingSessionUserInfo(payload: payload),
        )

        XCTAssertEqual(analytics.events, [.trainingSyncSucceeded])
        XCTAssertTrue(session.transferredUserInfos.isEmpty)
    }
```

- [ ] **Step 3: Run the sync tests and verify RED**

Run:

```bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/PhoneWatchSyncServiceTests
```

Expected: compilation fails because `PhoneWatchSyncService` does not accept the `analytics` dependency.

- [ ] **Step 4: Inject analytics and report after import success**

In `PhoneWatchSyncService`, add the property and defaulted initializer argument:

```swift
    private let analytics: AnalyticsTracking

    init(
        importer: TrainingSessionImporting,
        session: PhoneWatchConnectivitySessionProtocol? = nil,
        notificationCenter: NotificationCenter = .default,
        logger: AppLogging = AppLogger.shared,
        analytics: AnalyticsTracking = NoopAnalyticsTracker(),
        now: @escaping () -> Date = Date.init,
    ) {
        self.importer = importer
        self.session = session ?? PhoneWatchConnectivitySessionAdapter()
        self.notificationCenter = notificationCenter
        self.logger = logger
        self.analytics = analytics
        self.now = now
    }
```

Immediately after the successful import log and before the notification/ACK path, add:

```swift
        analytics.track(.trainingSyncSucceeded)
        notificationCenter.post(name: .trainingSessionsDidChange, object: nil)
```

Do not track payload receipt, decode failure, import failure, or ACK success/failure.

- [ ] **Step 5: Run the sync tests and verify GREEN**

Run the command from Step 3 again.

Expected: every sync-service test passes; a successful import reports once per received payload, and import failure reports nothing.

- [ ] **Step 6: Commit the sync call site**

Run:

```bash
git add \
  ShotMarker/Services/PhoneWatchSyncService.swift \
  ShotMarkerTests/PhoneWatchSyncServiceTests.swift \
  ShotMarkerTests/SpyAnalyticsTracker.swift
git diff --cached --check
git commit -m "feat: 上报训练同步成功事件"
```

Expected: one commit containing only the injected sync event and its spy/tests.

### Task 4: Report highlight generation and photo-library save success

**Files:**

- Modify: `ShotMarkerTests/HighlightJobManagerTests.swift`
- Modify: `ShotMarker/ViewModels/HighlightJobManager.swift`

- [ ] **Step 1: Add failing generation assertions**

In `testCreateJobCopiesFileVideosAndStartsWhenIdle`, inject `let analytics = SpyAnalyticsTracker()` into the manager and add:

```swift
        XCTAssertEqual(analytics.events, [.highlightGenerateSucceeded])
```

The existing `.immediateCompleted` runner deliberately calls `onChange(completed)` and then returns the completed job. This assertion is the regression test that prevents tracking from the callback and the final return path twice.

Add a failed-runner case:

```swift
    func testFailedHighlightGenerationDoesNotTrackSuccess() async throws {
        let analytics = SpyAnalyticsTracker()
        let manager = HighlightJobManager(
            store: InMemoryHighlightJobStore(),
            fileStore: HighlightJobFileStore(baseDirectoryURL: temporaryDirectory),
            runnerFactory: { _ in .immediateFailed },
            analytics: analytics,
        )

        _ = try await manager.createJob(
            session: makeSession(),
            selectedVideos: [makeSelectedVideo()],
            clipSettings: ClipSettings(secondsBeforeMarker: 9, secondsAfterMarker: 4),
        )
        await Task.yield()

        XCTAssertEqual(manager.jobs.first?.status, .failed)
        XCTAssertTrue(analytics.events.isEmpty)
    }
```

Add this test-only runner beside `.immediateCompleted`:

```swift
    static let immediateFailed = HighlightJobRunner(
        makeHighlightClip: { _, _, _ in URL(fileURLWithPath: "/tmp/unused.mov") },
        runOverride: { _, _ in
            throw HighlightJobRunnerTestError.failed
        },
    )
```

And add the test error:

```swift
private enum HighlightJobRunnerTestError: Error {
    case failed
}
```

- [ ] **Step 2: Add failing photo-library assertions**

Inject a `SpyAnalyticsTracker` into each existing save test, then assert:

```swift
// testSaveCompletedJobToPhotoLibraryMarksItSaved
XCTAssertEqual(analytics.events, [.highlightSaveSucceeded])

// testSaveAlreadySavedCompletedJobSavesAgainAndRefreshesSavedAt
XCTAssertEqual(analytics.events, [.highlightSaveSucceeded])

// testSaveCompletedJobToPhotoLibraryFailureLeavesJobCompletedAndRetryable
XCTAssertTrue(analytics.events.isEmpty)
```

The already-saved case represents a real repeated user save: every new successful Photos write emits one new success event.

- [ ] **Step 3: Run manager tests and verify RED**

Run:

```bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/HighlightJobManagerTests
```

Expected: compilation fails because `HighlightJobManager` does not accept the analytics dependency.

- [ ] **Step 4: Inject analytics into the manager and live factory**

Add the property and initializer argument:

```swift
    private let analytics: AnalyticsTracking

    init(
        store: HighlightJobStoreProtocol,
        fileStore: HighlightJobFileStoreProtocol,
        runnerFactory: @escaping (HighlightJob) -> HighlightJobRunner,
        saveVideoToPhotoLibrary: @escaping (URL) async throws -> Void = { _ in },
        logger: AppLogging = AppLogger.shared,
        analytics: AnalyticsTracking = NoopAnalyticsTracker(),
    ) {
        self.store = store
        self.fileStore = fileStore
        self.runnerFactory = runnerFactory
        self.saveVideoToPhotoLibrary = saveVideoToPhotoLibrary
        self.logger = logger
        self.analytics = analytics
    }
```

Change the live factory signature and pass the dependency through:

```swift
        static func live(
            logger: AppLogging = AppLogger.shared,
            analytics: AnalyticsTracking = NoopAnalyticsTracker(),
        ) -> HighlightJobManager {
```

And in its `HighlightJobManager(...)` call:

```swift
                logger: logger,
                analytics: analytics,
```

- [ ] **Step 5: Track only the final runner return**

Change the success path in `startNextQueuedJobIfPossible` to:

```swift
                let finalJob = try await runner.run(job: job) { updatedJob in
                    self.update(updatedJob)
                }
                self.update(finalJob)
                if finalJob.status == .completed {
                    analytics.track(.highlightGenerateSucceeded)
                }
```

Do not add tracking to `update(_:)` or the `onChange` closure; both handle intermediate and duplicate final state updates.

- [ ] **Step 6: Track only after Photos state is persisted**

In `saveToPhotoLibrary`, keep the existing successful Photos write and state mutation, then add tracking immediately after `persist()`:

```swift
            jobs[updatedIndex].photoLibrarySavedAt = Date()
            jobs[updatedIndex].photoLibrarySaveErrorMessage = nil
            jobs[updatedIndex].updatedAt = Date()
            persist()
            analytics.track(.highlightSaveSucceeded)
            logger.info(
```

Do not track missing output, denied permission, thrown save errors, or the start of a save attempt.

- [ ] **Step 7: Run manager tests and verify GREEN**

Run the command from Step 3 again.

Expected: all manager tests pass, generation produces exactly one event despite the duplicate completed-state callback, and failed generation/save paths produce no success event.

- [ ] **Step 8: Commit the highlight call sites**

Run:

```bash
git add \
  ShotMarker/ViewModels/HighlightJobManager.swift \
  ShotMarkerTests/HighlightJobManagerTests.swift
git diff --cached --check
git commit -m "feat: 上报集锦生成与保存成功事件"
```

Expected: one commit containing only manager injection, the two success call sites, and their tests.

### Task 5: Select live analytics only for iPhone Release builds

**Files:**

- Create: `ShotMarkerTests/AnalyticsRuntimePolicyTests.swift`
- Create: `ShotMarker/Services/Analytics/AnalyticsRuntimePolicy.swift`
- Modify: `ShotMarker/ShotMarkerApp.swift`

- [ ] **Step 1: Add the failing runtime-policy test**

Create `ShotMarkerTests/AnalyticsRuntimePolicyTests.swift`:

```swift
@testable import ShotMarker
import Foundation
import XCTest

final class AnalyticsRuntimePolicyTests: XCTestCase {
    func testOnlyReleaseIPhoneSendsAnalytics() {
        XCTAssertTrue(
            AnalyticsRuntimePolicy.shouldSend(isDebugBuild: false, isPhone: true),
        )
        XCTAssertFalse(
            AnalyticsRuntimePolicy.shouldSend(isDebugBuild: true, isPhone: true),
        )
        XCTAssertFalse(
            AnalyticsRuntimePolicy.shouldSend(isDebugBuild: false, isPhone: false),
        )
        XCTAssertFalse(
            AnalyticsRuntimePolicy.shouldSend(isDebugBuild: true, isPhone: false),
        )
    }
}
```

- [ ] **Step 2: Run the policy test and verify RED**

Run:

```bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/AnalyticsRuntimePolicyTests
```

Expected: compilation fails because `AnalyticsRuntimePolicy` does not exist.

- [ ] **Step 3: Implement the pure runtime policy**

Create `ShotMarker/Services/Analytics/AnalyticsRuntimePolicy.swift`:

```swift
import Foundation

nonisolated enum AnalyticsRuntimePolicy {
    static func shouldSend(isDebugBuild: Bool, isPhone: Bool) -> Bool {
        !isDebugBuild && isPhone
    }
}
```

- [ ] **Step 4: Compose one shared tracker in `ShotMarkerApp`**

Add the guarded UIKit import without changing the existing SwiftUI import:

```swift
import SwiftUI
#if os(iOS)
    import UIKit
#endif
```

Keep `GlitchTipCrashReporter.start()` at the beginning of `init()`. After creating `logger` and before creating `PhoneWatchSyncService`, add:

```swift
        #if DEBUG
            let isDebugBuild = true
        #else
            let isDebugBuild = false
        #endif
        #if os(iOS)
            let isPhone = UIDevice.current.userInterfaceIdiom == .phone
        #else
            let isPhone = false
        #endif

        let analytics: AnalyticsTracking
        if AnalyticsRuntimePolicy.shouldSend(
            isDebugBuild: isDebugBuild,
            isPhone: isPhone,
        ) {
            analytics = AnalyticsClient.live()
        } else {
            analytics = NoopAnalyticsTracker()
        }
```

Pass the same instance to both business services:

```swift
        let syncService = PhoneWatchSyncService(
            importer: TrainingSessionImporter(store: store),
            logger: logger,
            analytics: analytics,
        )
```

```swift
            let highlightJobManager = HighlightJobManager.live(
                logger: logger,
                analytics: analytics,
            )
```

After the existing local `app.launch` log and before `syncService.start()`, add:

```swift
        analytics.track(.appLaunch)
```

This position emits once for each iPhone Release app process, not for scene foreground changes or SwiftUI view reconstruction. Debug, Preview, unit-test composition, iPad, and non-iOS platforms receive the no-op implementation.

- [ ] **Step 5: Run policy and affected service tests and verify GREEN**

Run:

```bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/AnalyticsRuntimePolicyTests \
  -only-testing:ShotMarkerTests/PhoneWatchSyncServiceTests \
  -only-testing:ShotMarkerTests/HighlightJobManagerTests
```

Expected: all selected tests pass. Test execution does not contact `zhangrh.shop` because injected/default test dependencies are no-op.

- [ ] **Step 6: Build Release without launching it**

Run:

```bash
xcodebuild build \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator'
```

Expected: Release compilation succeeds, proving the real client branch builds. A build alone does not launch the app or send an event.

- [ ] **Step 7: Commit the composition root**

Run:

```bash
git add \
  ShotMarker/Services/Analytics/AnalyticsRuntimePolicy.swift \
  ShotMarker/ShotMarkerApp.swift \
  ShotMarkerTests/AnalyticsRuntimePolicyTests.swift
git diff --cached --check
git commit -m "feat: 仅在iPhone发布版启用埋点"
```

Expected: one commit that preserves GlitchTip startup and adds only analytics composition.

### Task 6: Add and verify the privacy manifest

**Files:**

- Create: `ShotMarkerTests/PrivacyManifestTests.swift`
- Create or merge: `ShotMarker/PrivacyInfo.xcprivacy`

- [ ] **Step 1: Add the failing manifest contract tests**

Create `ShotMarkerTests/PrivacyManifestTests.swift`:

```swift
@testable import ShotMarker
import Foundation
import XCTest

final class PrivacyManifestTests: XCTestCase {
    func testAnalyticsDataTypesAreLinkedForAnalyticsButNotTracking() throws {
        let manifest = try loadManifest()
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        let entries = try XCTUnwrap(
            manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]],
        )
        let entriesByType = Dictionary(
            uniqueKeysWithValues: entries.compactMap { entry in
                (entry["NSPrivacyCollectedDataType"] as? String).map { ($0, entry) }
            },
        )

        for type in [
            "NSPrivacyCollectedDataTypeDeviceID",
            "NSPrivacyCollectedDataTypeProductInteraction",
        ] {
            let entry = try XCTUnwrap(entriesByType[type])
            XCTAssertEqual(entry["NSPrivacyCollectedDataTypeLinked"] as? Bool, true)
            XCTAssertEqual(entry["NSPrivacyCollectedDataTypeTracking"] as? Bool, false)
            XCTAssertTrue(
                (entry["NSPrivacyCollectedDataTypePurposes"] as? [String])?
                    .contains("NSPrivacyCollectedDataTypePurposeAnalytics") == true,
            )
        }
    }

    func testRequiredReasonAPIsCoverAppOwnedDefaultsAndContainerFileMetadata() throws {
        let manifest = try loadManifest()
        let entries = try XCTUnwrap(
            manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]],
        )
        let reasonsByType = Dictionary(
            uniqueKeysWithValues: entries.compactMap { entry in
                guard let type = entry["NSPrivacyAccessedAPIType"] as? String,
                      let reasons = entry["NSPrivacyAccessedAPITypeReasons"] as? [String]
                else {
                    return nil
                }
                return (type, reasons)
            },
        )

        XCTAssertTrue(
            reasonsByType["NSPrivacyAccessedAPICategoryUserDefaults"]?
                .contains("CA92.1") == true,
        )
        XCTAssertTrue(
            reasonsByType["NSPrivacyAccessedAPICategoryFileTimestamp"]?
                .contains("C617.1") == true,
        )
    }

    private func loadManifest() throws -> [String: Any] {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repositoryRoot.appendingPathComponent("ShotMarker/PrivacyInfo.xcprivacy")
        let data = try Data(contentsOf: url)
        let value = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil,
        )
        return try XCTUnwrap(value as? [String: Any])
    }
}
```

- [ ] **Step 2: Run the manifest tests and verify RED**

Run:

```bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/PrivacyManifestTests
```

Expected: the test fails because `ShotMarker/PrivacyInfo.xcprivacy` is absent or lacks the approved entries.

- [ ] **Step 3: Create or merge the manifest**

If no app manifest exists after GlitchTip work is complete, create `ShotMarker/PrivacyInfo.xcprivacy` with this complete content:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyTracking</key>
    <false/>
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>CA92.1</string>
            </array>
        </dict>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>C617.1</string>
            </array>
        </dict>
    </array>
    <key>NSPrivacyCollectedDataTypes</key>
    <array>
        <dict>
            <key>NSPrivacyCollectedDataType</key>
            <string>NSPrivacyCollectedDataTypeDeviceID</string>
            <key>NSPrivacyCollectedDataTypeLinked</key>
            <true/>
            <key>NSPrivacyCollectedDataTypeTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypePurposes</key>
            <array>
                <string>NSPrivacyCollectedDataTypePurposeAnalytics</string>
            </array>
        </dict>
        <dict>
            <key>NSPrivacyCollectedDataType</key>
            <string>NSPrivacyCollectedDataTypeProductInteraction</string>
            <key>NSPrivacyCollectedDataTypeLinked</key>
            <true/>
            <key>NSPrivacyCollectedDataTypeTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypePurposes</key>
            <array>
                <string>NSPrivacyCollectedDataTypePurposeAnalytics</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
```

If a finalized app manifest already exists, do not replace it. Merge the two analytics dictionaries into its `NSPrivacyCollectedDataTypes`, merge the UserDefaults and FileTimestamp dictionaries into `NSPrivacyAccessedAPITypes`, set top-level `NSPrivacyTracking` to false, and preserve every unrelated entry. Do not duplicate a dictionary whose category already exists; merge reasons into the existing category.

`CA92.1` covers app-only UserDefaults used by clip settings and the installation identifier. `C617.1` covers metadata/size access for files inside the app container used by the local log store. These reasons describe the app's actual API use and do not authorize fingerprinting.

- [ ] **Step 4: Validate plist structure and tests**

Run:

```bash
plutil -lint ShotMarker/PrivacyInfo.xcprivacy
plutil -p ShotMarker/PrivacyInfo.xcprivacy | rg \
  "DeviceID|ProductInteraction|PurposeAnalytics|UserDefaults|CA92.1|FileTimestamp|C617.1"
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/PrivacyManifestTests
```

Expected: plist lint succeeds, all six expected categories/reasons appear, and the manifest tests pass.

- [ ] **Step 5: Verify the filesystem-synchronized target bundles the manifest**

Run:

```bash
SHOTMARKER_PRIVACY_DERIVED_DATA="$(mktemp -d)"
xcodebuild build \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$SHOTMARKER_PRIVACY_DERIVED_DATA"
test -f \
  "$SHOTMARKER_PRIVACY_DERIVED_DATA/Build/Products/Release-iphonesimulator/ShotMarker.app/PrivacyInfo.xcprivacy"
plutil -lint \
  "$SHOTMARKER_PRIVACY_DERIVED_DATA/Build/Products/Release-iphonesimulator/ShotMarker.app/PrivacyInfo.xcprivacy"
```

Expected: the app-level `PrivacyInfo.xcprivacy` exists and passes plist lint. If the file is absent, inspect synchronized-group target membership in Xcode and make the smallest project-file fix; do not regenerate or overwrite the existing GlitchTip package graph.

- [ ] **Step 6: Commit the privacy manifest**

Run:

```bash
git add \
  ShotMarker/PrivacyInfo.xcprivacy \
  ShotMarkerTests/PrivacyManifestTests.swift
git diff --cached --check
git commit -m "docs: 声明埋点与必需原因API隐私信息"
```

If Step 5 required a target-membership edit, add only the minimal `ShotMarker.xcodeproj/project.pbxproj` hunk after verifying it does not alter Sentry package references.

### Task 7: Run the complete client verification gate

- [ ] **Step 1: Run every ShotMarker unit test**

Run:

```bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests
```

Expected: the complete `ShotMarkerTests` bundle passes, including existing logging, sync, job, export, and GlitchTip tests.

- [ ] **Step 2: Run a clean Release simulator build**

Run:

```bash
SHOTMARKER_ANALYTICS_DERIVED_DATA="$(mktemp -d)"
xcodebuild build \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$SHOTMARKER_ANALYTICS_DERIVED_DATA"
test -f \
  "$SHOTMARKER_ANALYTICS_DERIVED_DATA/Build/Products/Release-iphonesimulator/ShotMarker.app/PrivacyInfo.xcprivacy"
```

Expected: Release build succeeds and the manifest exists at the app-bundle root. Do not launch this Release build during automated verification, because launch would intentionally send `app_launch`.

- [ ] **Step 3: Audit the outgoing-data boundary**

Run:

```bash
rg -n "URLQueryItem|track\(" ShotMarker/Services/Analytics ShotMarker/Services/PhoneWatchSyncService.swift ShotMarker/ViewModels/HighlightJobManager.swift ShotMarker/ShotMarkerApp.swift
rg -n "trainingSessionId|jobID|deviceModel|systemVersion|error|AppLog" ShotMarker/Services/Analytics
```

Expected:

- the client has exactly five fixed query items: `time`, `project`, `device_id`, `event`, and `params`, with `params` exactly `{}`;
- the four business call sites use enum cases only;
- the second search returns no analytics-client payload field carrying training, job, device, error, or local-log data.

- [ ] **Step 4: Review commits and worktree**

Run:

```bash
git status --short
git log --oneline -6
git diff HEAD~6..HEAD --stat
git diff --check HEAD~6..HEAD
```

Expected: the worktree is clean, six scoped analytics commits are present, and no unrelated GlitchTip or user files were rewritten by these commits.

### Task 8: Prepare the manual release disclosures

- [ ] **Step 1: Record the App Store Connect answers**

Before submitting the build, configure App Privacy conservatively as:

- Device ID — collected, linked to the user/device installation, purpose Analytics, not used for tracking.
- Product Interaction — collected, linked to the user/device installation, purpose Analytics, not used for tracking.
- No advertising use and no cross-company tracking; do not add an ATT prompt.
- Keep the separately required GlitchTip Crash Data and Other Diagnostic Data answers consistent with the finalized crash-reporting design.

- [ ] **Step 2: Require the public policy before App Store release**

The server plan must be implemented and the updated policy must be published at:

```text
https://zhangrh.shop/shotmarker/privacy
```

before distributing the analytics-enabled Release build. Publishing remains a separate explicit action.

- [ ] **Step 3: Perform an explicitly authorized production smoke test**

After Backend support, public policy, and the Release app are all deployed with user authorization:

1. Record the current aggregate value from `GET /api/track/summary?days=1&project=shotmarker`.
2. Launch one Release/TestFlight iPhone build once.
3. Query the same endpoint again and verify `app_launch` increased without exposing raw installation IDs.
4. Do not send fabricated production training/generation/save events solely for testing.

This smoke test is outside automated implementation because launching Release intentionally writes production analytics data.
