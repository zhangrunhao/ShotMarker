@testable import ShotMarker
import XCTest

final class MarkerLabelStyleTests: XCTestCase {
    func testDefaultMatchesProductSpecification() {
        XCTAssertEqual(
            MarkerLabelStyle.default,
            MarkerLabelStyle(
                fontSizeRatio: 0.10,
                normalizedCenterX: 0.15,
                normalizedCenterY: 0.10,
                textOpacity: 1.00,
                backgroundOpacity: 0.60,
            ),
        )
    }

    func testNormalizedClampsFiniteValuesAndDefaultsNonFiniteValues() {
        let style = MarkerLabelStyle(
            fontSizeRatio: -1,
            normalizedCenterX: 2,
            normalizedCenterY: .nan,
            textOpacity: -Double.infinity,
            backgroundOpacity: 4,
        )

        XCTAssertEqual(
            style.normalized,
            MarkerLabelStyle(
                fontSizeRatio: 0.04,
                normalizedCenterX: 1,
                normalizedCenterY: 0.10,
                textOpacity: 1,
                backgroundOpacity: 1,
            ),
        )
    }

    func testDecodingMissingStyleFieldFallsBackOnlyThatField() throws {
        let data = Data(
            #"{"fontSizeRatio":0.12,"normalizedCenterX":0.35,"textOpacity":0.75,"backgroundOpacity":0.25}"#.utf8,
        )

        let decoded = try JSONDecoder().decode(MarkerLabelStyle.self, from: data)

        XCTAssertEqual(decoded.fontSizeRatio, 0.12)
        XCTAssertEqual(decoded.normalizedCenterX, 0.35)
        XCTAssertEqual(decoded.normalizedCenterY, 0.10)
        XCTAssertEqual(decoded.textOpacity, 0.75)
        XCTAssertEqual(decoded.backgroundOpacity, 0.25)
    }

    func testDecodingWrongFieldTypeThrows() {
        let data = Data(#"{"fontSizeRatio":"large"}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(MarkerLabelStyle.self, from: data))
    }

    func testEncodingWritesNormalizedFiniteValues() throws {
        let style = MarkerLabelStyle(
            fontSizeRatio: .infinity,
            normalizedCenterX: -1,
            normalizedCenterY: 2,
            textOpacity: 0.4,
            backgroundOpacity: 0.2,
        )

        let decoded = try JSONDecoder().decode(
            MarkerLabelStyle.self,
            from: JSONEncoder().encode(style),
        )

        XCTAssertEqual(
            decoded,
            MarkerLabelStyle(
                fontSizeRatio: 0.10,
                normalizedCenterX: 0,
                normalizedCenterY: 1,
                textOpacity: 0.4,
                backgroundOpacity: 0.2,
            ),
        )
    }
}
