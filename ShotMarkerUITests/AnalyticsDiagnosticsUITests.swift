import XCTest

final class AnalyticsDiagnosticsUITests: XCTestCase {
    func testSelfUseSwitchIsReachableFromLongPressAndPersists() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        openDiagnostics(app)
        let toggle = app.switches["analytics.selfUse"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let original = toggle.value as? String
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let changed = original == "1" ? "0" : "1"
        XCTAssertTrue(NSPredicate(format: "value == %@", changed).evaluate(with: toggle)
            || XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", changed), object: toggle)], timeout: 3) == .completed)
        app.buttons["完成"].tap()
        app.terminate()
        app.launch()
        openDiagnostics(app)
        XCTAssertEqual(toggle.value as? String, changed)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", original ?? "0"), object: toggle)], timeout: 3), .completed)
        app.buttons["完成"].tap()
    }

    private func openDiagnostics(_ app: XCUIApplication) {
        let title = app.navigationBars["训练记录"].staticTexts["训练记录"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        title.press(forDuration: 5.2)
        XCTAssertTrue(app.navigationBars["诊断"].waitForExistence(timeout: 5))
    }
}
