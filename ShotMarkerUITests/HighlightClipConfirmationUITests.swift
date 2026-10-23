import XCTest

final class HighlightClipConfirmationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchHarness()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testGalleryExposesReviewStatesAndUnreviewedDoesNotDisableGeneration() {
        XCTAssertTrue(app.staticTexts["未看 · 默认保留"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["已保留"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["已排除"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["视频不可用"].firstMatch.exists)
        XCTAssertTrue(app.buttons["确认并生成"].isEnabled)
    }

    func testExclusionAdvancesToAdjacentClipAndUndoRestoresOriginalDecision() {
        app.buttons["片段 1"].tap()
        app.buttons["ClipExclude"].tap()
        XCTAssertTrue(app.navigationBars["片段 2 / 5"].waitForExistence(timeout: 3))
        app.buttons["ClipPrevious"].tap()
        XCTAssertTrue(app.navigationBars["片段 1 / 5"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["已排除"].exists)
        app.buttons["ClipNext"].tap()
        app.buttons["ClipUndo"].tap()
        XCTAssertTrue(app.navigationBars["片段 1 / 5"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["未看 · 默认保留"].exists)
        XCTAssertFalse(app.buttons["ClipUndo"].exists)
    }

    func testDirtyNavigationCanContinueOrDiscardWithoutChangingSavedRange() {
        app.buttons["片段 2"].tap()
        let start = element(label: "片段起点")
        let originalValue = start.value as? String
        let origin = start.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        origin.press(forDuration: 0.1, thenDragTo: origin.withOffset(CGVector(dx: -32, dy: 0)))
        XCTAssertTrue(app.staticTexts["调整未保存"].waitForExistence(timeout: 2))
        app.buttons["ClipNext"].tap()
        XCTAssertTrue(app.alerts["放弃本次调整？"].waitForExistence(timeout: 2))
        app.alerts.buttons["继续调整"].tap()
        XCTAssertTrue(app.navigationBars["片段 2 / 5"].exists)
        app.buttons["ClipNext"].tap()
        app.alerts.buttons["放弃"].tap()
        XCTAssertTrue(app.navigationBars["片段 3 / 5"].waitForExistence(timeout: 3))
        app.buttons["ClipPrevious"].tap()
        XCTAssertTrue(app.navigationBars["片段 2 / 5"].waitForExistence(timeout: 3))
        XCTAssertEqual(element(label: "片段起点").value as? String, originalValue)
        XCTAssertTrue(app.staticTexts["已保留"].exists)
    }

    func testDirectDecisionVisitsConfirmedAndExcludedClipsWithoutRenumbering() {
        app.buttons["片段 1"].tap()
        for number in 2 ... 5 {
            app.buttons["ClipKeep"].tap()
            XCTAssertTrue(app.navigationBars["片段 \(number) / 5"].waitForExistence(timeout: 3))
        }
        XCTAssertFalse(app.buttons["ClipKeep"].isEnabled)
        app.buttons["ClipExclude"].tap()
        XCTAssertTrue(app.navigationBars["审核集锦片段"].waitForExistence(timeout: 3))
        app.buttons["片段 3"].tap()
        XCTAssertTrue(app.navigationBars["片段 3 / 5"].waitForExistence(timeout: 3))
        let strip = app.scrollViews["ClipNavigationStrip"]
        for _ in 0 ..< 5 where !strip.isHittable || strip.frame.maxY > app.frame.maxY - 200 {
            let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.72))
            origin.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.32)))
        }
        strip.swipeRight()
        XCTAssertTrue(app.buttons["ClipStrip-1"].isHittable)
        app.buttons["ClipStrip-1"].tap()
        XCTAssertTrue(app.navigationBars["片段 1 / 5"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["ClipPrevious"].isEnabled)
    }

    func testMaximumDynamicTypeKeepsDecisionsAndNavigationAccessible() {
        app.terminate()
        app = launchHarness(extraArguments: [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ])
        app.buttons["片段 1"].tap()
        for identifier in ["ClipExclude", "ClipKeep", "ClipNext"] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.isHittable, identifier)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        }
        app.buttons["ClipExclude"].tap()
        XCTAssertTrue(app.navigationBars["片段 2 / 5"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["ClipPrevious"].isHittable)
    }

    private func launchHarness(extraArguments: [String] = []) -> XCUIApplication {
        let application = XCUIApplication()
        application.launchEnvironment["SHOTMARKER_UI_TEST_CLIP_CONFIRMATION"] = "1"
        application.launchArguments += extraArguments
        application.launch()
        XCTAssertTrue(application.navigationBars["审核集锦片段"].waitForExistence(timeout: 5))
        return application
    }

    private func element(label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }
}
