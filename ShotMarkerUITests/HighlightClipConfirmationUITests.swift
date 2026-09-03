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

    func testGalleryExposesAllFourStatesAndDefaultDoesNotDisableGeneration() {
        XCTAssertTrue(app.staticTexts["默认"].exists)
        XCTAssertTrue(app.staticTexts["已确认 · 保留"].exists)
        XCTAssertTrue(app.staticTexts["已确认 · 排除"].exists)
        XCTAssertTrue(app.staticTexts["视频不可用"].exists)
        XCTAssertTrue(app.buttons["确认并生成"].isEnabled)
    }

    func testPreciseControlsStartCollapsedAndResetAfterReentry() {
        app.buttons["片段 1"].tap()
        let disclosure = app.buttons["精确范围调整"]
        scrollUntilHittable(disclosure)
        XCTAssertTrue(disclosure.isHittable)
        XCTAssertFalse(app.buttons["-0.5s 更早"].exists)
        disclosure.tap()
        let fineTuneButton = app.buttons["-0.5s 更早"].firstMatch
        scrollUntilHittable(fineTuneButton)
        XCTAssertTrue(fineTuneButton.isHittable)
        scrollToTop()
        app.buttons["返回"].tap()
        XCTAssertFalse(app.alerts["放弃本次调整？"].exists)
        XCTAssertTrue(app.navigationBars["审核集锦片段"].waitForExistence(timeout: 2))
        app.buttons["片段 1"].tap()
        scrollUntilHittable(app.buttons["精确范围调整"])
        XCTAssertFalse(app.buttons["-0.5s 更早"].exists)
    }

    func testDirtyBackCanContinueOrDiscardWithoutChangingGallery() {
        app.buttons["片段 2"].tap()
        let inclusionToggle = app.switches["保留此片段"]
        scrollUntilHittable(inclusionToggle)
        XCTAssertTrue(inclusionToggle.isHittable)
        inclusionToggle.tap()
        scrollToTop()
        XCTAssertTrue(app.staticTexts["默认"].exists)
        app.buttons["返回"].tap()
        XCTAssertTrue(app.alerts["放弃本次调整？"].waitForExistence(timeout: 2))
        app.alerts.buttons["继续调整"].tap()
        XCTAssertTrue(app.navigationBars.matching(
            NSPredicate(format: "identifier BEGINSWITH '片段'")
        ).firstMatch.exists)
        app.buttons["返回"].tap()
        app.alerts.buttons["放弃"].tap()
        XCTAssertTrue(app.staticTexts["已确认 · 保留"].waitForExistence(timeout: 2))
    }

    func testConfirmationSkipsConfirmedCardThenReturnsAfterLastDefault() {
        app.buttons["片段 1"].tap()
        app.buttons["确认片段"].tap()
        XCTAssertTrue(app.navigationBars["片段 3"].waitForExistence(timeout: 2))
        app.buttons["确认片段"].tap()
        XCTAssertTrue(app.navigationBars["审核集锦片段"].waitForExistence(timeout: 2))
    }

    func testMaximumDynamicTypeKeepsStatusesAndConfirmationActionAccessible() {
        app.terminate()
        app = launchHarness(extraArguments: [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ])

        for title in ["默认", "已确认 · 保留", "已确认 · 排除", "视频不可用"] {
            let status = findStaticText(title)
            XCTAssertTrue(status.exists)
            XCTAssertFalse(
                String(describing: status.value ?? "").isEmpty,
                "\(title) 应提供非空辅助功能值",
            )
        }

        let confirmButton = app.buttons["确认并生成"]
        scrollUntilHittable(confirmButton)
        XCTAssertTrue(confirmButton.exists)
        XCTAssertTrue(confirmButton.isHittable)
        XCTAssertGreaterThanOrEqual(confirmButton.frame.height, 44)
    }

    private func launchHarness(extraArguments: [String] = []) -> XCUIApplication {
        let application = XCUIApplication()
        application.launchEnvironment["SHOTMARKER_UI_TEST_CLIP_CONFIRMATION"] = "1"
        application.launchArguments += extraArguments
        application.launch()
        XCTAssertTrue(application.navigationBars["审核集锦片段"].waitForExistence(timeout: 5))
        return application
    }

    private func findStaticText(_ title: String) -> XCUIElement {
        let element = app.staticTexts[title].firstMatch
        for _ in 0 ..< 8 where !element.exists {
            swipeContentUp()
        }
        return element
    }

    private func scrollUntilHittable(_ element: XCUIElement) {
        let safeTop = app.frame.minY + 100
        let safeBottom = app.frame.maxY - 190

        for _ in 0 ..< 8 {
            if element.exists {
                let midpoint = element.frame.midY
                if element.isHittable, midpoint >= safeTop, midpoint <= safeBottom {
                    return
                }
                if midpoint < safeTop {
                    swipeContentDown()
                    continue
                }
            }
            swipeContentUp()
        }
    }

    private func scrollToTop() {
        for _ in 0 ..< 6 {
            swipeContentDown()
        }
    }

    private func swipeContentUp() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.72))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.30))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func swipeContentDown() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.30))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.72))
        start.press(forDuration: 0.05, thenDragTo: end)
    }
}
