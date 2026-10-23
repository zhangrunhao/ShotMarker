@testable import ShotMarker
import CoreGraphics
import XCTest

final class ClipFramingTests: XCTestCase {
    func testNormalizationRoundsAndClampsGestureValuesWithoutChangingRawInput() {
        let raw = ClipFraming(scale: 2.24, centerX: 0.123456, centerY: 0.987654)
        XCTAssertEqual(raw.scale, 2.24)
        XCTAssertFalse(raw.isValid)
        let framing = raw.normalized
        XCTAssertEqual(framing.scale, 2.2)
        XCTAssertEqual(framing.centerX, 1 / 4.4, accuracy: 0.000_000_001)
        XCTAssertEqual(framing.centerY, 1 - 1 / 4.4, accuracy: 0.000_000_001)
        XCTAssertTrue(framing.isValid)
        XCTAssertEqual(framing.normalized, framing)
        XCTAssertEqual(ClipFraming(scale: 2.76, centerX: 0.456789, centerY: 0.543216).normalized,
            ClipFraming(scale: 2.8, centerX: 0.45679, centerY: 0.54322))
        XCTAssertEqual(ClipFraming(scale: -10, centerX: 0, centerY: 1).normalized, .original)
        XCTAssertEqual(ClipFraming(scale: 99, centerX: -10, centerY: 10).normalized,
            ClipFraming(scale: 4, centerX: 0.125, centerY: 0.875))
    }

    func testClampedEdgesRemainCanonicalAcrossAllSupportedScales() {
        for tenth in 10...40 {
            let framing = ClipFraming(scale: Double(tenth) / 10, centerX: -1, centerY: 2).normalized
            XCTAssertTrue(framing.isValid, "scale \(framing.scale)")
            XCTAssertEqual(framing.normalized, framing)
            XCTAssertEqual(framing.normalizedCropRect.minX, 0, accuracy: 0.000_000_001)
            XCTAssertEqual(framing.normalizedCropRect.maxY, 1, accuracy: 0.000_000_001)
        }
    }

    func testValidationRejectsNonfiniteOutOfBoundsAndUnnormalizedPersistence() throws {
        let invalid = [
            ClipFraming(scale: .nan, centerX: 0.5, centerY: 0.5),
            ClipFraming(scale: .infinity, centerX: 0.5, centerY: 0.5),
            ClipFraming(scale: 2, centerX: -.infinity, centerY: 0.5),
            ClipFraming(scale: 2, centerX: 0.5, centerY: .nan),
            ClipFraming(scale: 0.9, centerX: 0.5, centerY: 0.5),
            ClipFraming(scale: 4.1, centerX: 0.5, centerY: 0.5),
            ClipFraming(scale: 2.21, centerX: 0.5, centerY: 0.5),
            ClipFraming(scale: 2, centerX: 0.24999, centerY: 0.5),
            ClipFraming(scale: 2, centerX: 0.5, centerY: 0.75001),
            ClipFraming(scale: 2, centerX: 0.500001, centerY: 0.5),
            ClipFraming(scale: 1, centerX: 0.4, centerY: 0.5),
        ]
        for framing in invalid { XCTAssertFalse(framing.isValid, "\(framing)") }
        let decoded = try JSONDecoder().decode(ClipFraming.self,
            from: Data(#"{"scale":99,"centerX":0.1,"centerY":0.9}"#.utf8))
        XCTAssertEqual(decoded.scale, 99)
        XCTAssertFalse(decoded.isValid)
        XCTAssertTrue(ClipFraming.original.isValid)
        XCTAssertEqual(ClipFraming(scale: .nan, centerX: .infinity, centerY: -.infinity).normalized, .original)
    }

    func testNormalizedCropRectUsesTopLeftCoordinatesAndPreservesSourceAspect() {
        XCTAssertEqual(ClipFraming.original.normalizedCropRect, CGRect(x: 0, y: 0, width: 1, height: 1))
        let framing = ClipFraming(scale: 4, centerX: 0.125, centerY: 0.875)
        XCTAssertEqual(framing.normalizedCropRect, CGRect(x: 0, y: 0.75, width: 0.25, height: 0.25))
        XCTAssertEqual(ClipFramingGeometry.cropRect(framing: framing,
            in: CGRect(x: -20, y: 10, width: 1920, height: 1080)),
            CGRect(x: -20, y: 820, width: 480, height: 270))
    }

    func testUprightBoundsHandleRotationTranslationAndMirroring() {
        let landscape = CGSize(width: 1920, height: 1080)
        XCTAssertEqual(ClipFramingGeometry.uprightBounds(naturalSize: landscape,
            preferredTransform: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)),
            CGRect(x: 0, y: 0, width: 1080, height: 1920))
        XCTAssertEqual(ClipFramingGeometry.uprightBounds(naturalSize: landscape,
            preferredTransform: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 1920, ty: 0)),
            CGRect(x: 0, y: 0, width: 1920, height: 1080))
        XCTAssertEqual(ClipFramingGeometry.uprightBounds(naturalSize: landscape,
            preferredTransform: CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 5, ty: 7)),
            CGRect(x: 5, y: -1913, width: 1080, height: 1920))
    }

    func testAspectFitExcludesPlayerLetterboxingFromSourceGeometry() {
        XCTAssertEqual(ClipFramingGeometry.aspectFitRect(sourceSize: CGSize(width: 1920, height: 1080),
            in: CGRect(x: 10, y: 20, width: 400, height: 400)),
            CGRect(x: 10, y: 107.5, width: 400, height: 225))
        XCTAssertEqual(ClipFramingGeometry.aspectFitRect(sourceSize: CGSize(width: 1080, height: 1920),
            in: CGRect(x: 0, y: 0, width: 400, height: 225)),
            CGRect(x: 136.71875, y: 0, width: 126.5625, height: 225))
        XCTAssertEqual(ClipFramingGeometry.aspectFitRect(sourceSize: .zero,
            in: CGRect(x: 0, y: 0, width: 400, height: 225)), .zero)
        XCTAssertTrue(ClipFramingGeometry.cropRect(framing: ClipFraming(scale: 99, centerX: 0.5, centerY: 0.5),
            in: CGRect(x: 0, y: 0, width: 1920, height: 1080)).isNull)
    }
}
