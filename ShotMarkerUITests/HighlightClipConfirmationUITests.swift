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

    func testUnavailableFramingPreviewAllowsScrollingTheEditor() {
        app.buttons["片段 1"].tap()
        XCTAssertFalse(app.buttons["ClipFramingIncrease"].isEnabled)
        let preview = app.otherElements["ClipFramingPreview"]
        let timelineStart = element(label: "片段起点")
        let originalY = timelineStart.frame.minY
        let center = preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.press(forDuration: 0.1, thenDragTo: center.withOffset(CGVector(dx: 0, dy: -130)))
        XCTAssertLessThan(timelineStart.frame.minY, originalY - 50, "不可调整取景时，在预览区域拖动应能正常滚动编辑器")
        XCTAssertFalse(app.staticTexts["调整未保存"].exists)
    }

    func testExclusionAdvancesToAdjacentClipAndUndoRestoresOriginalDecision() {
        app.buttons["片段 1"].tap()
        app.buttons["ClipExclude"].tap()
        XCTAssertTrue(app.navigationBars["片段 2 / 5"].waitForExistence(timeout: 3))
        selectClip(1)
        XCTAssertTrue(app.navigationBars["片段 1 / 5"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["已排除"].exists)
        selectClip(2)
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
        selectClip(3)
        XCTAssertTrue(app.alerts["放弃本次调整？"].waitForExistence(timeout: 2))
        app.alerts.buttons["继续调整"].tap()
        XCTAssertTrue(app.navigationBars["片段 2 / 5"].exists)
        selectClip(3)
        app.alerts.buttons["放弃"].tap()
        XCTAssertTrue(app.navigationBars["片段 3 / 5"].waitForExistence(timeout: 3))
        selectClip(2)
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
        for _ in 0 ..< 5 where !strip.isHittable || strip.frame.maxY > app.buttons["ClipExclude"].frame.minY - 8 {
            let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.72))
            origin.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.32)))
        }
        strip.swipeRight()
        XCTAssertTrue(app.buttons["ClipStrip-1"].isHittable)
        app.buttons["ClipStrip-1"].tap()
        XCTAssertTrue(app.navigationBars["片段 1 / 5"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["ClipPrevious"].exists)
        XCTAssertFalse(app.buttons["ClipNext"].exists)
    }

    func testMaximumDynamicTypeKeepsDecisionsAndNavigationAccessible() {
        app.terminate()
        app = launchHarness(extraArguments: [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ])
        app.buttons["片段 1"].tap()
        for identifier in ["ClipExclude", "ClipKeep"] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.isHittable, identifier)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        }
        app.buttons["ClipExclude"].tap()
        XCTAssertTrue(app.navigationBars["片段 2 / 5"].waitForExistence(timeout: 3))
        selectClip(1)
        XCTAssertTrue(app.navigationBars["片段 1 / 5"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["ClipStrip-1"].exists)
        let restore = app.buttons["ClipFramingRestore"]
        revealContentElement(restore)
        XCTAssertTrue(restore.isHittable)
        XCTAssertGreaterThanOrEqual(restore.frame.height, 44)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "maximum-dynamic-type-framing-controls"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private var contentBottom: CGFloat {
        let excludeTop = app.buttons["ClipExclude"].frame.minY
        let undo = app.buttons["ClipUndo"]
        return (undo.exists ? min(undo.frame.minY, excludeTop) : excludeTop) - 24
    }

    private func revealContentElement(_ element: XCUIElement) {
        let top = app.navigationBars.firstMatch.frame.maxY + 24
        for _ in 0..<16 {
            let bottom = contentBottom
            let target = element.frame
            if target.minY >= top, target.maxY <= bottom { break }
            let scrollDown = target.maxY > bottom
            let overflow = scrollDown ? target.maxY - bottom : top - target.minY
            let distance = min(max(overflow + 20, 60), (bottom - top) * 0.7)
            let startY = scrollDown ? bottom : top
            let endY = scrollDown ? bottom - distance : top + distance
            let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: startY / app.frame.height))
            origin.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: endY / app.frame.height)))
        }
        XCTAssertGreaterThanOrEqual(element.frame.minY, top - 1, "控件应完全位于导航栏下方")
        XCTAssertLessThanOrEqual(element.frame.maxY, contentBottom + 1, "控件应完全位于固定决定区域上方")
    }

    private func selectClip(_ number: Int) {
        let strip = app.scrollViews["ClipNavigationStrip"]
        revealContentElement(strip)
        let button = app.buttons["ClipStrip-\(number)"]
        if !button.isHittable { number == 1 ? strip.swipeRight() : strip.swipeLeft() }
        XCTAssertTrue(button.isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "clip-strip-accessible"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        button.tap()
    }

    private func launchHarness(extraArguments: [String] = []) -> XCUIApplication {
        let application = XCUIApplication()
        application.launchEnvironment["SHOTMARKER_UI_TEST_CLIP_CONFIRMATION"] = "1"
        application.launchArguments += extraArguments
        if extraArguments.contains("UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge") {
            application.launchEnvironment["SHOTMARKER_UI_TEST_MAX_DYNAMIC_TYPE"] = "1"
        }
        application.launch()
        XCTAssertTrue(application.navigationBars["审核集锦片段"].waitForExistence(timeout: 5))
        return application
    }

    private func element(label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }
}
