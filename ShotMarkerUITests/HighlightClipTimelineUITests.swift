import XCTest

final class HighlightClipTimelineUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["SHOTMARKER_UI_TEST_TIMELINE"] = "1"
        app.launch()
        XCTAssertTrue(app.navigationBars["时间轴拖动测试"].waitForExistence(timeout: 5))
    }

    func testStartHandleDragChangesOnlyStartAndDuration() {
        drag("片段起点", horizontalOffset: 36)

        XCTAssertGreaterThan(value("TimelineStartValue"), 5)
        XCTAssertEqual(value("TimelineEndValue"), 9, accuracy: 0.001)
        XCTAssertLessThan(value("TimelineDurationValue"), 4)
        XCTAssertEqual(value("TimelinePlayheadValue"), 2, accuracy: 0.001)
    }

    func testEndHandleDragChangesOnlyEndAndDuration() {
        drag("片段终点", horizontalOffset: 36)

        XCTAssertEqual(value("TimelineStartValue"), 5, accuracy: 0.001)
        XCTAssertGreaterThan(value("TimelineEndValue"), 9)
        XCTAssertGreaterThan(value("TimelineDurationValue"), 4)
        XCTAssertEqual(value("TimelinePlayheadValue"), 2, accuracy: 0.001)
    }

    func testWholeRangeDragMovesBothBoundsWithoutChangingDuration() {
        drag("移动整个片段", horizontalOffset: 36)

        XCTAssertGreaterThan(value("TimelineStartValue"), 5)
        XCTAssertGreaterThan(value("TimelineEndValue"), 9)
        XCTAssertEqual(value("TimelineDurationValue"), 4, accuracy: 0.001)
        XCTAssertEqual(value("TimelinePlayheadValue"), 2, accuracy: 0.001)
    }

    func testPlayheadDragChangesOnlyPreviewPosition() {
        drag("预览位置", horizontalOffset: 36)

        XCTAssertEqual(value("TimelineStartValue"), 5, accuracy: 0.001)
        XCTAssertEqual(value("TimelineEndValue"), 9, accuracy: 0.001)
        XCTAssertEqual(value("TimelineDurationValue"), 4, accuracy: 0.001)
        XCTAssertGreaterThan(value("TimelinePlayheadValue"), 2)
    }

    private func drag(
        _ label: String,
        horizontalOffset: CGFloat,
    ) {
        let element = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label))
            .firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(element.frame.width, 43.5)
        XCTAssertLessThanOrEqual(element.frame.width, 52.5)
        XCTAssertEqual(element.frame.height, 44, accuracy: 0.5)
        let origin = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        origin.press(
            forDuration: 0.1,
            thenDragTo: origin.withOffset(CGVector(dx: horizontalOffset, dy: 0)),
        )
    }

    private func value(_ identifier: String) -> Double {
        let element = app.staticTexts[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: 2))
        let parts = element.label.split(separator: " ")
        guard let last = parts.last, let value = Double(last) else {
            XCTFail("无法解析 \(identifier) 的值：\(element.label)")
            return .nan
        }
        return value
    }
}
