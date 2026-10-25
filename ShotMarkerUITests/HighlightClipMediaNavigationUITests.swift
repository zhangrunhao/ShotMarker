import XCTest
import UIKit

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

    func testNavigatingFromLoadingClipRejectsItsLateMediaAndPreservesSavedRange() {
        app.terminate()
        app.launchEnvironment["SHOTMARKER_UI_TEST_DELAY_REOPENED_CLIP"] = "1"
        app.launch()
        XCTAssertTrue(app.navigationBars["审核集锦片段"].waitForExistence(timeout: 20))
        app.buttons["片段 1"].tap()
        assertLoadedClip(title: "片段 1 / 3", start: 1)
        let start = element(label: "片段起点")
        let origin = start.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        origin.press(forDuration: 0.1, thenDragTo: origin.withOffset(CGVector(dx: 48, dy: 0)))
        let savedStart = seconds(start)
        XCTAssertGreaterThan(savedStart, 1.5, "必须先保存与默认起点不同的范围")
        app.buttons["ClipKeep"].tap()
        assertLoadedClip(title: "片段 2 / 3", start: 691.1)

        selectClip(1)
        XCTAssertTrue(app.navigationBars["片段 1 / 3"].waitForExistence(timeout: 5))
        let releaseLoad = app.buttons["ClipMediaReleasePlaybackLoad"]
        XCTAssertTrue(releaseLoad.waitForExistence(timeout: 5), "重新打开首段的旧播放载入必须仍在等待")
        selectClip(3)
        assertLoadedClip(title: "片段 3 / 3", start: 21)
        releaseLoad.tap()
        XCTAssertTrue(app.staticTexts["ClipMediaDelayedLoadFinished"].waitForExistence(timeout: 5),
            "先让上一片段的载入返回，再核验当前片段的播放状态")
        assertLoadedClip(title: "片段 3 / 3", start: 21)
        assertPlaybackAdvances(after: 21)
        selectClip(1)
        assertLoadedClip(title: "片段 1 / 3", start: savedStart)
        XCTAssertTrue(app.staticTexts["已保留"].exists)
        assertPlaybackAdvances(after: savedStart)
    }

    func testFramingControlsPersistContinueAndManualNavigationRestoresOwnValue() {
        app.buttons["片段 1"].tap()
        assertLoadedClip(title: "片段 1 / 3", start: 1)
        XCTAssertFalse(app.buttons["ClipPrevious"].exists)
        XCTAssertFalse(app.buttons["ClipNext"].exists)
        setScale(2.2)
        openOperationsIfNeeded()
        XCTAssertGreaterThanOrEqual(app.buttons["ClipFramingRestore"].frame.height, 44)
        recordScreenshot("landscape-framing-2.2x")
        app.buttons["ClipKeep"].tap()
        assertLoadedClip(title: "片段 2 / 3", start: 691.1)
        XCTAssertEqual(element(label: "取景倍率").value as? String, "2.2 倍")
        selectClip(2)
        assertLoadedClip(title: "片段 2 / 3", start: 691.1)
        scrollToPreview()
        XCTAssertEqual(element(label: "取景倍率").value as? String, "1.0 倍")
        assertPlaybackAdvances(after: 691.1)
        selectClip(1)
        XCTAssertFalse(app.alerts["放弃本次调整？"].exists)
        assertLoadedClip(title: "片段 1 / 3", start: 1)
        scrollToPreview()
        XCTAssertEqual(element(label: "取景倍率").value as? String, "2.2 倍")
        selectClip(2)
        assertLoadedClip(title: "片段 2 / 3", start: 691.1)
        scrollToPreview()
        XCTAssertEqual(element(label: "取景倍率").value as? String, "1.0 倍")
        setScale(2)
        app.buttons["ClipExclude"].tap()
        assertLoadedClip(title: "片段 3 / 3", start: 21)
        XCTAssertEqual(element(label: "取景倍率").value as? String, "1.0 倍")
        selectClip(1)
        assertLoadedClip(title: "片段 1 / 3", start: 1)
        scrollToPreview()
        openOperationsIfNeeded()
        app.buttons["ClipFramingRestore"].tap()
        XCTAssertEqual(element(label: "取景倍率").value as? String, "1.0 倍")
        XCTAssertEqual(seconds(element(label: "片段起点")), 1, accuracy: 0.11)
        app.buttons["ClipKeep"].tap()
        assertLoadedClip(title: "片段 2 / 3", start: 691.1)
        XCTAssertEqual(element(label: "取景倍率").value as? String, "2.0 倍")
    }

    func testPortraitPreviewCropsOnlySourcePixelsAndGesturesStayPaused() {
        app.buttons["片段 3"].tap()
        assertLoadedClip(title: "片段 3 / 3", start: 21)
        let preview = app.otherElements["ClipFramingPreview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        assertPreviewPixel(preview, x: 0.05, y: 0.3, color: .red)
        assertPreviewPixel(preview, x: 0.5, y: 0.3, color: .green)
        assertOuterPillarboxBlack(preview)
        setScale(2)
        assertPreviewPixel(preview, x: 0.05, y: 0.3, color: .green)
        assertPreviewPixel(preview, x: 0.5, y: 0.5, color: .yellow)
        assertOuterPillarboxBlack(preview)
        recordScreenshot("upright-source-framing-2x")
        app.buttons["播放片段"].tap()
        let viewportWidth = preview.frame.height * 90 / 160
        let center = preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.press(forDuration: 0.1, thenDragTo: center.withOffset(CGVector(dx: viewportWidth * 0.6, dy: 0)))
        XCTAssertTrue(app.buttons["播放片段"].exists)
        assertPreviewPixel(preview, x: 0.05, y: 0.3, color: .red)
        assertOuterPillarboxBlack(preview)
        openOperationsIfNeeded()
        app.buttons["ClipFramingRestore"].tap()
        preview.pinch(withScale: 2, velocity: 2)
        XCTAssertTrue(app.buttons["播放片段"].exists)
        let multiplier = element(label: "取景倍率").value as? String ?? ""
        XCTAssertNotEqual(multiplier, "1.0 倍")
        assertOuterPillarboxBlack(preview)
    }

    func testRotatedSourcePreviewUsesUprightCoordinates() {
        app.terminate()
        app.launchEnvironment["SHOTMARKER_UI_TEST_ROTATED_CLIP_SOURCE"] = "1"
        app.launch()
        XCTAssertTrue(app.navigationBars["审核集锦片段"].waitForExistence(timeout: 20))
        app.buttons["片段 1"].tap()
        assertLoadedClip(title: "片段 1 / 3", start: 1)
        let preview = app.otherElements["ClipFramingPreview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        assertPreviewPixel(preview, x: 0.05, y: 0.3, color: .red)
        assertPreviewPixel(preview, x: 0.5, y: 0.3, color: .green)
        assertOuterPillarboxBlack(preview)
        setScale(2)
        assertPreviewPixel(preview, x: 0.05, y: 0.3, color: .green)
        assertPreviewPixel(preview, x: 0.5, y: 0.5, color: .yellow)
        assertOuterPillarboxBlack(preview)
        recordScreenshot("upright-source-framing-2x")
    }

    func testNumberOperationListSeparatesModesAndStaysActiveWhenCollapsed() {
        app.buttons["片段 1"].tap()
        assertLoadedClip(title: "片段 1 / 3", start: 1)
        let operations = app.buttons["ClipOperationsToggle"]
        XCTAssertTrue(operations.waitForExistence(timeout: 5))
        XCTAssertFalse(app.sliders["ClipNumberSize"].exists)
        operations.tap()
        recordScreenshot("framing-operations-expanded")
        app.buttons["ClipFramingToggle"].tap()
        XCTAssertFalse(app.buttons["ClipFramingIncrease"].isEnabled)
        app.buttons["ClipNumberToggle"].tap()
        XCTAssertTrue(app.sliders["ClipNumberSize"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["ClipFramingIncrease"].isEnabled)
        XCTAssertFalse(app.buttons["ClipFramingRestore"].isEnabled)
        operations.tap()
        XCTAssertFalse(app.buttons["ClipNumberToggle"].exists)
        XCTAssertTrue(app.sliders["ClipNumberSize"].exists)
        app.sliders["ClipNumberSize"].adjust(toNormalizedSliderPosition: 1)
        XCTAssertEqual(element(label: "取景倍率").value as? String, "1.0 倍")
        recordScreenshot("number-editing-collapsed-operations")
        operations.tap()
        app.buttons["ClipNumberToggle"].tap()
        XCTAssertFalse(app.sliders["ClipNumberSize"].exists)
        XCTAssertTrue(app.buttons["ClipFramingIncrease"].isEnabled)
        app.buttons["ClipNumberToggle"].tap()
        app.buttons["ClipFramingToggle"].tap()
        XCTAssertFalse(app.sliders["ClipNumberSize"].exists)
        XCTAssertTrue(app.buttons["ClipFramingIncrease"].isEnabled)
        app.buttons["返回"].tap()
        XCTAssertTrue(app.alerts["放弃本次调整？"].waitForExistence(timeout: 3))
        app.alerts.buttons["放弃"].tap()
        XCTAssertTrue(app.navigationBars["审核集锦片段"].waitForExistence(timeout: 5))
    }

    func testNumberPlacementSavesInheritsAndManualNavigationRestoresOwnLayout() {
        app.buttons["片段 1"].tap()
        assertLoadedClip(title: "片段 1 / 3", start: 1)
        openOperationsIfNeeded()
        app.buttons["ClipNumberToggle"].tap()
        let size = app.sliders["ClipNumberSize"]
        XCTAssertTrue(size.waitForExistence(timeout: 5))
        size.adjust(toNormalizedSliderPosition: 1)
        let position = app.otherElements["ClipNumberPosition"]
        XCTAssertTrue(position.waitForExistence(timeout: 5))
        let start = position.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5))
        let finish = position.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.8))
        start.press(forDuration: 0.1, thenDragTo: finish)
        let savedPosition = position.value as? String
        XCTAssertNotNil(savedPosition)
        XCTAssertNotEqual(savedPosition, "横向 15%，纵向 10%，字号 16%")
        XCTAssertEqual(element(label: "取景倍率").value as? String, "1.0 倍")
        recordScreenshot("number-placement-adjusted")
        app.buttons["ClipKeep"].tap()
        assertLoadedClip(title: "片段 2 / 3", start: 691.1)
        XCTAssertEqual(app.sliders["ClipNumberSize"].value as? String, "16%")
        XCTAssertEqual(app.otherElements["ClipNumberPosition"].value as? String, savedPosition)
        selectClip(2)
        assertLoadedClip(title: "片段 2 / 3", start: 691.1)
        XCTAssertEqual(app.sliders["ClipNumberSize"].value as? String, "10%")
        selectClip(1)
        assertLoadedClip(title: "片段 1 / 3", start: 1)
        XCTAssertEqual(app.otherElements["ClipNumberPosition"].value as? String, savedPosition)
        app.buttons["ClipKeep"].tap()
        assertLoadedClip(title: "片段 2 / 3", start: 691.1)
        app.buttons["ClipKeep"].tap()
        assertLoadedClip(title: "片段 3 / 3", start: 21)
        XCTAssertEqual(app.sliders["ClipNumberSize"].value as? String, "10%")
        selectClip(2)
        assertLoadedClip(title: "片段 2 / 3", start: 691.1)
        XCTAssertEqual(app.otherElements["ClipNumberPosition"].value as? String, savedPosition)
    }

    private func openOperationsIfNeeded() {
        if !app.buttons["ClipFramingRestore"].exists { app.buttons["ClipOperationsToggle"].tap() }
    }

    private func setScale(_ scale: Double) {
        let increase = app.buttons["ClipFramingIncrease"]
        XCTAssertTrue(increase.waitForExistence(timeout: 5))
        XCTAssertTrue(increase.isEnabled)
        for _ in 0..<Int(((scale - 1) * 10).rounded()) { increase.tap() }
        XCTAssertEqual(element(label: "取景倍率").value as? String, String(format: "%.1f 倍", scale))
    }

    private func selectClip(_ number: Int) {
        let strip = app.scrollViews["ClipNavigationStrip"]
        for _ in 0..<8 where !strip.isHittable || strip.frame.maxY > app.buttons["ClipExclude"].frame.minY - 8 {
            let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.72))
            origin.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.3)))
        }
        let button = app.buttons["ClipStrip-\(number)"]
        if !button.isHittable { number == 1 ? strip.swipeRight() : strip.swipeLeft() }
        XCTAssertTrue(button.isHittable)
        button.tap()
    }

    private func scrollToPreview() {
        for _ in 0..<8 where !app.buttons["ClipFramingIncrease"].isHittable {
            let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.3))
            origin.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.75)))
        }
    }

    private func recordScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private enum MarkerColor { case red, green, yellow, black }

    private func assertOuterPillarboxBlack(_ preview: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        assertScreenshotPixel(CGPoint(x: preview.frame.minX + 8, y: preview.frame.midY), color: .black, file: file, line: line)
        assertScreenshotPixel(CGPoint(x: preview.frame.maxX - 8, y: preview.frame.midY), color: .black, file: file, line: line)
    }

    private func assertPreviewPixel(_ preview: XCUIElement, x: Double, y: Double, color: MarkerColor, file: StaticString = #filePath, line: UInt = #line) {
        let width = preview.frame.height * 90 / 160
        let point = CGPoint(x: preview.frame.midX + (x - 0.5) * width, y: preview.frame.minY + y * preview.frame.height)
        assertScreenshotPixel(point, color: color, file: file, line: line)
    }

    private func assertScreenshotPixel(_ point: CGPoint, color: MarkerColor, file: StaticString = #filePath, line: UInt = #line) {
        let matches = NSPredicate { _, _ in
            guard let image = self.app.screenshot().image.cgImage else { return false }
            let width = image.width, height = image.height
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let x = min(width - 1, max(0, Int(point.x * Double(width) / self.app.frame.width)))
            let y = min(height - 1, max(0, Int(point.y * Double(height) / self.app.frame.height)))
            let offset = (y * width + x) * 4
            let r = pixels[offset], g = pixels[offset + 1], b = pixels[offset + 2]
            switch color {
            case .red: return r > 160 && g < 100 && b < 100
            case .green: return g > 120 && r < 100 && b < 100
            case .yellow: return r > 160 && g > 160 && b < 100
            case .black: return r < 35 && g < 35 && b < 35
            }
        }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: matches, object: nil)], timeout: 6)
        if result != .completed {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertEqual(result, .completed, "预览像素应呈现 \(color)，位置 \(point)", file: file, line: line)
    }

    private func assertLoadedClip(title: String, start: Double) {
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
        let position = element(label: "预览位置")
        let positioned = NSPredicate { _, _ in
            abs(self.seconds(position) - start) < 0.11
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: positioned, object: nil)], timeout: 10), .completed,
            "\(title) 应定位到新片段起点，实际为 \(position.value ?? "无")")
        let progress = element(label: "片段播放进度")
        XCTAssertEqual(seconds(progress), 0, accuracy: 0.11, "新片段应从自身零秒开始显示进度")
        let frames = app.staticTexts["ClipMediaLoadedFrameCount"]
        XCTAssertTrue(frames.waitForExistence(timeout: 5))
        let extracted = NSPredicate(format: "label == '8'")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: extracted, object: frames)], timeout: 10), .completed)
        XCTAssertGreaterThan(element(label: "片段终点").frame.midX - element(label: "片段起点").frame.midX, 80,
            "时间轴必须围绕新片段展开，起止手柄不能挤在同一侧")
        let play = app.buttons["播放片段"]
        // Expanded operations or number controls can require scrolling on a narrow
        // screen. Reveal playback according to its geometry in every editing mode.
        for _ in 0..<8 where play.frame.maxY > app.buttons["ClipExclude"].frame.minY - 8 {
            let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.72))
            origin.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.45)))
        }
        XCTAssertEqual(seconds(position), start, accuracy: 0.11, "滚动显示播放按钮不应改变预览位置")
        XCTAssertEqual(seconds(progress), 0, accuracy: 0.11, "滚动显示播放按钮不应改变播放进度")
        XCTAssertTrue(play.isHittable, "播放按钮应可达并可操作")
        XCTAssertGreaterThanOrEqual(play.frame.minY, app.navigationBars.firstMatch.frame.maxY)
        XCTAssertLessThanOrEqual(play.frame.maxY, app.buttons["ClipExclude"].frame.minY - 8,
            "播放按钮必须完整位于固定决定区域上方")
        for identifier in ["ClipExclude", "ClipKeep"] {
            XCTAssertTrue(app.frame.contains(app.buttons[identifier].frame), "决定按钮必须完整位于屏幕内")
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = title
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func assertPlaybackAdvances(after start: Double) {
        app.buttons["播放片段"].tap()
        let position = element(label: "预览位置")
        let advancing = NSPredicate { _, _ in self.seconds(position) > start + 0.2 }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: advancing, object: nil)], timeout: 5), .completed)
        XCTAssertGreaterThan(seconds(element(label: "片段播放进度")), 0.2)
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
