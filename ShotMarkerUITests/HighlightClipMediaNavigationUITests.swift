import XCTest

final class HighlightClipMediaNavigationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["SHOTMARKER_UI_TEST_CLIP_CONFIRMATION"] = "1"
        app.launchEnvironment["SHOTMARKER_UI_TEST_CLIP_MEDIA"] = "1"
        app.launch()
        XCTAssertTrue(app.navigationBars["审核集锦片段"].waitForExistence(timeout: 20))
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testConfirmingMergedClipLoadsNextClipAndThenAnotherSource() {
        app.buttons["片段 1"].tap()
        assertLoadedClip(title: "片段 1 / 3", start: 1)

        app.buttons["ClipKeep"].tap()
        assertLoadedClip(title: "片段 2 / 3", start: 691.1)
        assertPlaybackAdvances(after: 691.1)

        app.buttons["ClipKeep"].tap()
        assertLoadedClip(title: "片段 3 / 3", start: 21)
        assertPlaybackAdvances(after: 21)

        app.buttons["ClipKeep"].tap()
        XCTAssertTrue(app.navigationBars["审核集锦片段"].waitForExistence(timeout: 5))
        app.buttons["片段 2"].tap()
        assertLoadedClip(title: "片段 2 / 3", start: 691.1)
    }

    func testUndoWhileReopenedClipIsLoadingRejectsTheLateUndoneRange() {
        app.terminate()
        app.launchEnvironment["SHOTMARKER_UI_TEST_DELAY_REOPENED_CLIP"] = "1"
        app.launch()
        XCTAssertTrue(app.navigationBars["审核集锦片段"].waitForExistence(timeout: 20))
        app.buttons["片段 1"].tap()
        assertLoadedClip(title: "片段 1 / 3", start: 1)
        let start = element(label: "片段起点")
        let origin = start.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        origin.press(forDuration: 0.1, thenDragTo: origin.withOffset(CGVector(dx: 48, dy: 0)))
        XCTAssertGreaterThan(seconds(start), 1.5, "必须先保存与默认起点不同的范围")
        app.buttons["ClipKeep"].tap()
        assertLoadedClip(title: "片段 2 / 3", start: 691.1)

        app.buttons["ClipPrevious"].tap()
        XCTAssertTrue(app.navigationBars["片段 1 / 3"].waitForExistence(timeout: 5))
        let releaseLoad = app.buttons["ClipMediaReleasePlaybackLoad"]
        XCTAssertTrue(releaseLoad.waitForExistence(timeout: 5), "重新打开首段的旧播放载入必须仍在等待")
        app.buttons["ClipUndo"].tap()
        XCTAssertTrue(app.staticTexts["未看 · 默认保留"].waitForExistence(timeout: 5))
        let restoredRange = NSPredicate { _, _ in
            abs(self.seconds(self.element(label: "片段起点")) - 1) < 0.11
                && abs(self.seconds(self.element(label: "片段终点")) - 18) < 0.11
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: restoredRange, object: nil)], timeout: 5), .completed)
        releaseLoad.tap()
        XCTAssertTrue(app.staticTexts["ClipMediaDelayedLoadFinished"].waitForExistence(timeout: 5),
            "先让携带旧范围的载入返回，再核验播放状态")

        assertLoadedClip(title: "片段 1 / 3", start: 1)
        assertPlaybackAdvances(after: 1)
    }

    private func assertLoadedClip(title: String, start: Double) {
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
        let position = element(label: "当前位置")
        let positioned = NSPredicate { _, _ in
            abs(self.seconds(position) - start) < 0.11
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: positioned, object: nil)], timeout: 10), .completed,
            "\(title) 应定位到新片段起点，实际为 \(position.value ?? "无")")
        let frames = app.staticTexts["ClipMediaLoadedFrameCount"]
        XCTAssertTrue(frames.waitForExistence(timeout: 5))
        let extracted = NSPredicate(format: "label == '8'")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: extracted, object: frames)], timeout: 10), .completed)
        XCTAssertGreaterThan(element(label: "片段终点").frame.midX - element(label: "片段起点").frame.midX, 80,
            "时间轴必须围绕新片段展开，起止手柄不能挤在同一侧")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = title
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func assertPlaybackAdvances(after start: Double) {
        app.buttons["播放片段"].tap()
        let position = element(label: "当前位置")
        let advancing = NSPredicate { _, _ in self.seconds(position) > start + 0.2 }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: advancing, object: nil)], timeout: 5), .completed)
        app.buttons["暂停"].tap()
    }

    private func element(label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func seconds(_ element: XCUIElement) -> Double {
        let text = element.value as? String ?? ""
        let components = text.split(whereSeparator: { !$0.isNumber && $0 != "." }).compactMap { Double($0) }
        if text.contains("分"), components.count == 2 {
            return components[0] * 60 + components[1]
        }
        return components.first ?? .nan
    }
}
