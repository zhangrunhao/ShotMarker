@testable import ShotMarker
import XCTest

final class MarkerLabelLayoutTests: XCTestCase {
    private let frame = CGRect(x: 0, y: 0, width: 200, height: 100)
    private let labelSize = CGSize(width: 20, height: 10)

    func testAspectFitRectPreservesVerticalImageInsideLandscapePreview() {
        let result = MarkerLabelLayout.aspectFitRect(
            contentSize: CGSize(width: 1080, height: 1920),
            in: CGRect(x: 0, y: 0, width: 320, height: 180),
        )

        XCTAssertEqual(result.minX, 109.375, accuracy: 0.001)
        XCTAssertEqual(result.minY, 0, accuracy: 0.001)
        XCTAssertEqual(result.width, 101.25, accuracy: 0.001)
        XCTAssertEqual(result.height, 180, accuracy: 0.001)
    }

    func testTopLeftCenterAndBottomRightStayInsideFrame() {
        XCTAssertEqual(
            MarkerLabelLayout.previewCenter(
                for: CGPoint(x: 0, y: 0),
                labelSize: labelSize,
                in: frame,
            ),
            CGPoint(x: 10, y: 5),
        )
        XCTAssertEqual(
            MarkerLabelLayout.previewCenter(
                for: CGPoint(x: 0.5, y: 0.5),
                labelSize: labelSize,
                in: frame,
            ),
            CGPoint(x: 100, y: 50),
        )
        XCTAssertEqual(
            MarkerLabelLayout.previewCenter(
                for: CGPoint(x: 1, y: 1),
                labelSize: labelSize,
                in: frame,
            ),
            CGPoint(x: 190, y: 95),
        )
    }

    func testDraggedPointReturnsClampedNormalizedCenter() {
        let result = MarkerLabelLayout.normalizedCenter(
            forPreviewPoint: CGPoint(x: 220, y: 120),
            labelSize: labelSize,
            in: frame,
        )

        XCTAssertEqual(result.x, 0.95, accuracy: 0.0001)
        XCTAssertEqual(result.y, 0.95, accuracy: 0.0001)
    }

    func testLongLabelMovesFartherInsideAtSameNormalizedCenter() {
        let center = CGPoint(x: 0.98, y: 0.5)
        let shortOrigin = MarkerLabelLayout.clampedOrigin(
            for: center,
            labelSize: CGSize(width: 20, height: 10),
            in: frame,
        )
        let longOrigin = MarkerLabelLayout.clampedOrigin(
            for: center,
            labelSize: CGSize(width: 100, height: 10),
            in: frame,
        )

        XCTAssertEqual(shortOrigin.x, 180)
        XCTAssertEqual(longOrigin.x, 100)
    }

    func testLandscapeAndPortraitUseSameNormalizedSemantics() {
        let normalized = CGPoint(x: 0.25, y: 0.75)
        let landscape = MarkerLabelLayout.previewCenter(
            for: normalized,
            labelSize: .zero,
            in: CGRect(x: 0, y: 0, width: 200, height: 100),
        )
        let portrait = MarkerLabelLayout.previewCenter(
            for: normalized,
            labelSize: .zero,
            in: CGRect(x: 0, y: 0, width: 100, height: 200),
        )

        XCTAssertEqual(landscape, CGPoint(x: 50, y: 75))
        XCTAssertEqual(portrait, CGPoint(x: 25, y: 150))
    }

    func testDifferentLabelSizesUseTheirActualBounds() {
        let normalized = CGPoint(x: 0.02, y: 0.02)
        let small = MarkerLabelLayout.clampedOrigin(
            for: normalized,
            labelSize: CGSize(width: 20, height: 10),
            in: frame,
        )
        let large = MarkerLabelLayout.clampedOrigin(
            for: normalized,
            labelSize: CGSize(width: 80, height: 40),
            in: frame,
        )

        XCTAssertEqual(small, CGPoint(x: 0, y: 0))
        XCTAssertEqual(large, CGPoint(x: 0, y: 0))
        XCTAssertEqual(
            MarkerLabelLayout.previewCenter(
                for: normalized,
                labelSize: CGSize(width: 80, height: 40),
                in: frame,
            ),
            CGPoint(x: 40, y: 20),
        )
    }

    func testCoreImageOriginFlipsTopLeftYIntoBottomLeftCoordinates() {
        let result = MarkerLabelLayout.coreImageOrigin(
            for: CGPoint(x: 0.25, y: 0.25),
            labelSize: labelSize,
            in: CGRect(x: 10, y: 20, width: 200, height: 100),
        )

        XCTAssertEqual(result.x, 50, accuracy: 0.0001)
        XCTAssertEqual(result.y, 90, accuracy: 0.0001)
    }
}
