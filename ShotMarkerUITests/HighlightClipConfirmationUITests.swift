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

    func testExcludedClipCanBeReopenedAndKeptThroughTheNavigationStrip() {
        app.buttons["片段 1"].tap()
        app.buttons["ClipExclude"].tap()
        XCTAssertTrue(app.navigationBars["片段 2 / 5"].waitForExistence(timeout: 3))
        selectClip(1)
        XCTAssertTrue(app.navigationBars["片段 1 / 5"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["已排除"].exists)
        app.buttons["ClipKeep"].tap()
        XCTAssertTrue(app.navigationBars["片段 2 / 5"].waitForExistence(timeout: 3))
        selectClip(1)
        XCTAssertTrue(app.navigationBars["片段 1 / 5"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["已保留"].exists)
        app.buttons["返回"].tap()
        XCTAssertTrue(app.navigationBars["审核集锦片段"].waitForExistence(timeout: 3))
        app.buttons["片段 1"].tap()
        XCTAssertTrue(app.staticTexts["已保留"].exists)
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
        ], loadsMedia: true)
        app.buttons["片段 1"].tap()
        for identifier in ["ClipExclude", "ClipKeep"] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.isHittable, identifier)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
            XCTAssertTrue(app.frame.contains(button.frame), "固定决定按钮必须完整位于屏幕内")
        }
        let play = app.buttons["播放片段"]
        revealContentElement(play)
        XCTAssertTrue(play.isHittable)
        let enabled = NSPredicate(format: "enabled == true")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: enabled, object: play)], timeout: 10), .completed)
        play.tap()
        XCTAssertTrue(app.buttons["暂停"].waitForExistence(timeout: 3))
        let playbackScreenshot = XCTAttachment(screenshot: app.screenshot())
        playbackScreenshot.name = "maximum-dynamic-type-playback-and-decisions"
        playbackScreenshot.lifetime = .keepAlways
        add(playbackScreenshot)
        app.buttons["暂停"].tap()
        app.buttons["ClipExclude"].tap()
        XCTAssertTrue(app.navigationBars["片段 2 / 3"].waitForExistence(timeout: 3))
        selectClip(1)
        XCTAssertTrue(app.navigationBars["片段 1 / 3"].waitForExistence(timeout: 3))
        let operations = app.buttons["ClipOperationsToggle"]
        revealContentElement(operations)
        operations.tap()
        let restore = app.buttons["ClipFramingRestore"]
        revealContentElement(restore)
        XCTAssertTrue(restore.isHittable)
        XCTAssertGreaterThanOrEqual(restore.frame.height, 44)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "maximum-dynamic-type-framing-controls"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let number = app.buttons["ClipNumberToggle"]
        revealContentElement(number)
        XCTAssertGreaterThanOrEqual(number.frame.height, 44)
        number.tap()
        let size = app.sliders["ClipNumberSize"]
        revealContentElement(size)
        XCTAssertTrue(size.isHittable)
        size.adjust(toNormalizedSliderPosition: 1)
        XCTAssertEqual(size.value as? String, "16%")
        let numberScreenshot = XCTAttachment(screenshot: app.screenshot())
        numberScreenshot.name = "maximum-dynamic-type-number-controls"
        numberScreenshot.lifetime = .keepAlways
        add(numberScreenshot)
    }

    private var contentBottom: CGFloat {
        app.buttons["ClipExclude"].frame.minY - 24
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
            let visibleContent = CGRect(x: 0, y: top, width: app.frame.width, height: bottom - top)
            let labels = ["未看 · 默认保留", "已保留", "已排除", "调整未保存", "取景倍率", "片段播放进度", "全部片段"]
            let textFrames = app.staticTexts.matching(NSPredicate(
                format: "label IN %@ OR identifier == 'ClipRelationships'", labels
            )).allElementsBoundByIndex.map { $0.frame.intersection(visibleContent) }
                .filter { !$0.isNull && $0.height >= 20 }
            let startFrame = scrollDown
                ? textFrames.max(by: { $0.midY < $1.midY })
                : textFrames.min(by: { $0.midY < $1.midY })
            guard let startFrame else { break }
            // Start inside visible content: blank padding does not reliably receive scrolling,
            // while the preview and timeline reserve their own drag gestures.
            let startY = scrollDown ? startFrame.maxY - 8 : startFrame.minY + 8
            let endY = scrollDown ? max(top + 4, startY - distance) : min(bottom - 4, startY + distance)
            let origin = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: startFrame.midX, dy: startY))
            origin.press(forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: startFrame.midX, dy: endY)),
                withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        if element.frame.minY < top - 1 || element.frame.maxY > contentBottom + 1 {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "unreachable-editor-control"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "unreachable-editor-control"
            screenshot.lifetime = .keepAlways
            add(screenshot)
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

    private func launchHarness(extraArguments: [String] = [], loadsMedia: Bool = false) -> XCUIApplication {
        let application = XCUIApplication()
        application.launchEnvironment["SHOTMARKER_UI_TEST_CLIP_CONFIRMATION"] = "1"
        application.launchArguments += extraArguments
        if loadsMedia {
            application.launchEnvironment["SHOTMARKER_UI_TEST_CLIP_MEDIA"] = "1"
        }
        if extraArguments.contains("UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge") {
            application.launchEnvironment["SHOTMARKER_UI_TEST_MAX_DYNAMIC_TYPE"] = "1"
        }
        application.launch()
        XCTAssertTrue(application.navigationBars["审核集锦片段"].waitForExistence(timeout: 20))
        return application
    }

    private func element(label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }
}
