# Watch Digital Crown 打点 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Digital Crown marker input on Apple Watch so training users can record markers after a clear rotation threshold, while keeping the existing long-press and double-tap flow.

**Architecture:** Keep `WatchTrainingViewModel` as the only training state machine. Add a small internal Crown threshold helper in `WatchTrainingView.swift`, test it through the existing Watch test target, and have the SwiftUI view translate Digital Crown changes into the existing `handleDoubleTap()` marker action plus success haptics.

**Tech Stack:** SwiftUI, WatchKit, XCTest, watchOS Digital Crown APIs.

---

## File Structure

- Modify: `ShotMarkerWatchApp/Views/WatchTrainingView.swift`
  - Owns Watch-specific input handling, haptics, long-press animation, Digital Crown focus, and the Crown threshold helper.
- Modify: `ShotMarkerWatchApp/ViewModels/WatchTrainingViewModel.swift`
  - Only update training-state display text so users know both double-tap and Crown marker input are available.
- Modify: `ShotMarkerWatchAppTests/WatchTrainingViewModelTests.swift`
  - Keep existing ViewModel tests and add tests for the internal Crown threshold helper. Reusing this file avoids editing `ShotMarker.xcodeproj/project.pbxproj` for a new test file.

No iPhone app files, sync service files, payload models, or Xcode project membership should change.

## Task 1: Add Tested Crown Threshold Helper

**Files:**
- Modify: `ShotMarkerWatchApp/Views/WatchTrainingView.swift`
- Test: `ShotMarkerWatchAppTests/WatchTrainingViewModelTests.swift`

- [ ] **Step 1: Add failing tests for Crown threshold behavior**

Append these tests inside `final class WatchTrainingViewModelTests: XCTestCase`, before the closing brace:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarkerWatchApp -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.5' -only-testing:ShotMarkerWatchAppTests/WatchTrainingViewModelTests
```

Expected: FAIL because `CrownMarkerThresholdTracker` is not defined.

- [ ] **Step 3: Add the minimal threshold helper**

Append this internal helper at file scope in `ShotMarkerWatchApp/Views/WatchTrainingView.swift`, after the `WatchTrainingView` closing brace:

```swift
struct CrownMarkerThresholdTracker: Equatable {
    let threshold: Double
    private(set) var baseline: Double

    init(threshold: Double, baseline: Double = 0) {
        precondition(threshold > 0, "Crown marker threshold must be positive.")
        self.threshold = threshold
        self.baseline = baseline
    }

    mutating func reset(baseline: Double) {
        self.baseline = baseline
    }

    mutating func update(currentValue: Double) -> Bool {
        guard abs(currentValue - baseline) >= threshold else {
            return false
        }

        baseline = currentValue
        return true
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarkerWatchApp -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.5' -only-testing:ShotMarkerWatchAppTests/WatchTrainingViewModelTests
```

Expected: PASS. If this local machine still has the known watch simulator runtime mismatch, capture the exact simulator/runtime error and continue to the build step later for compile feedback.

- [ ] **Step 5: Commit**

```bash
git add ShotMarkerWatchApp/Views/WatchTrainingView.swift ShotMarkerWatchAppTests/WatchTrainingViewModelTests.swift
git commit -m "test: 添加手表旋钮打点阈值测试"
```

## Task 2: Wire Digital Crown Input Into Watch Training View

**Files:**
- Modify: `ShotMarkerWatchApp/Views/WatchTrainingView.swift`
- Modify: `ShotMarkerWatchApp/ViewModels/WatchTrainingViewModel.swift`
- Test: `ShotMarkerWatchAppTests/WatchTrainingViewModelTests.swift`

- [ ] **Step 1: Update the training-state button title test**

In `testLongPressStartsTrainingFromNotTrainingState`, change the training-state title assertion to:

```swift
        XCTAssertEqual(viewModel.buttonTitle, "双击/旋钮打点\n长按结束")
```

- [ ] **Step 2: Run the title test to verify it fails**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarkerWatchApp -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.5' -only-testing:ShotMarkerWatchAppTests/WatchTrainingViewModelTests/testLongPressStartsTrainingFromNotTrainingState
```

Expected: FAIL because the current title is `双击打点 / 长按结束`.

- [ ] **Step 3: Update WatchTrainingViewModel training title**

In `ShotMarkerWatchApp/ViewModels/WatchTrainingViewModel.swift`, change only the `.training` branch of `buttonTitle`:

```swift
    var buttonTitle: String {
        switch state {
        case .notTraining:
            "长按开始"
        case .training:
            "双击/旋钮打点\n长按结束"
        }
    }
```

- [ ] **Step 4: Add Crown state and constants to the Watch view**

In `ShotMarkerWatchApp/Views/WatchTrainingView.swift`, add these state properties near the existing `@State` properties:

```swift
    @State private var crownRotationValue = 0.0
    @State private var crownMarkerThresholdTracker = CrownMarkerThresholdTracker(
        threshold: 8,
    )
```

Add these constants near the existing duration constants:

```swift
    private let crownRotationLowerBound = -10_000.0
    private let crownRotationUpperBound = 10_000.0
```

- [ ] **Step 5: Add Crown focus, rotation binding, and change handlers**

After the existing `.padding()` modifier on the outer `VStack`, add:

```swift
        .focusable(true)
        .digitalCrownRotation(
            $crownRotationValue,
            from: crownRotationLowerBound,
            through: crownRotationUpperBound,
            by: 1,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: false,
        )
        .onChange(of: crownRotationValue) { _, newValue in
            handleCrownRotationChange(newValue)
        }
        .onChange(of: viewModel.state) { _, _ in
            crownMarkerThresholdTracker.reset(baseline: crownRotationValue)
        }
```

Keep the existing `.sheet(isPresented:)` after these modifiers, so the final modifier order is:

```swift
        .padding()
        .focusable(true)
        .digitalCrownRotation(...)
        .onChange(of: crownRotationValue) { _, newValue in
            handleCrownRotationChange(newValue)
        }
        .onChange(of: viewModel.state) { _, _ in
            crownMarkerThresholdTracker.reset(baseline: crownRotationValue)
        }
        .sheet(isPresented: $isShowingDiagnostics) {
            WatchSyncDiagnosticsView(snapshotProvider: syncService.diagnosticsSnapshot)
        }
```

- [ ] **Step 6: Add the Crown marker handler**

Add this private method inside `WatchTrainingView`, near the gesture helpers:

```swift
    private func handleCrownRotationChange(_ newValue: Double) {
        guard viewModel.state == .training else {
            crownMarkerThresholdTracker.reset(baseline: newValue)
            return
        }

        guard crownMarkerThresholdTracker.update(currentValue: newValue) else {
            return
        }

        if viewModel.handleDoubleTap() {
            WKInterfaceDevice.current().play(.success)
        }
    }
```

- [ ] **Step 7: Run the focused Watch tests**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarkerWatchApp -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.5' -only-testing:ShotMarkerWatchAppTests/WatchTrainingViewModelTests
```

Expected: PASS, or the same local watch simulator runtime mismatch already captured in Task 1.

- [ ] **Step 8: Run Watch build**

Run:

```bash
xcodebuild build -project ShotMarker.xcodeproj -scheme ShotMarkerWatchApp -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.5' CODE_SIGNING_ALLOWED=NO
```

Expected: PASS. If simulator runtime selection fails on this machine, retry with an available watchOS simulator from `xcrun simctl list devices available`, then record the exact command and result.

- [ ] **Step 9: Commit**

```bash
git add ShotMarkerWatchApp/Views/WatchTrainingView.swift ShotMarkerWatchApp/ViewModels/WatchTrainingViewModel.swift ShotMarkerWatchAppTests/WatchTrainingViewModelTests.swift
git commit -m "feat: 支持手表旋钮阈值打点"
```

## Task 3: Full Regression Verification

**Files:**
- No source changes expected.

- [ ] **Step 1: Run all Watch app tests**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarkerWatchApp -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.5'
```

Expected: PASS. If unavailable simulator runtimes block execution, record the exact error and list available watch simulators with:

```bash
xcrun simctl list devices available | rg "Apple Watch"
```

- [ ] **Step 2: Run iPhone tests to confirm shared payload and sync paths were not affected**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: PASS.

- [ ] **Step 3: Inspect git diff**

Run:

```bash
git diff --stat HEAD
git diff -- ShotMarkerWatchApp/Views/WatchTrainingView.swift ShotMarkerWatchApp/ViewModels/WatchTrainingViewModel.swift ShotMarkerWatchAppTests/WatchTrainingViewModelTests.swift
```

Expected: Only Watch view input handling, Watch title text, and Watch tests changed.

- [ ] **Step 4: Manual real-device verification**

On a paired physical Apple Watch:

1. Open ShotMarker Watch app.
2. Long-press the main circle and confirm training starts.
3. Double-tap the main circle and confirm marker count increases by 1 with success haptic.
4. Rotate the Digital Crown lightly and confirm marker count does not change.
5. Rotate the Digital Crown clearly past the threshold and confirm marker count increases by 1 with success haptic.
6. Long-press the main circle and confirm training ends.
7. Open the iPhone app and confirm the completed training session syncs with the expected marker count.

- [ ] **Step 5: Commit verification notes if source changed during fixes**

Only run this if verification required additional source edits:

```bash
git add ShotMarkerWatchApp/Views/WatchTrainingView.swift ShotMarkerWatchApp/ViewModels/WatchTrainingViewModel.swift ShotMarkerWatchAppTests/WatchTrainingViewModelTests.swift
git commit -m "fix: 修正手表旋钮打点验证问题"
```
