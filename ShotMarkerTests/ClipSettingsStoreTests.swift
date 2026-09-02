@testable import ShotMarker
import XCTest

final class ClipSettingsStoreTests: XCTestCase {
    private var suiteName: String!
    private var userDefaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "ShotMarker.ClipSettingsStoreTests.\(UUID().uuidString)"
        userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        suiteName = nil
    }

    func testDefaultClipSettingsUseNineSecondsBeforeAndFourSecondsAfterMarker() {
        XCTAssertEqual(
            ClipSettings.default,
            ClipSettings(secondsBeforeMarker: 9, secondsAfterMarker: 4, markerLabelStyle: .default),
        )
    }

    func testLoadReturnsDefaultSettingsWhenNothingHasBeenSaved() {
        let store = ClipSettingsStore(userDefaults: userDefaults)

        XCTAssertEqual(store.load(), .default)
    }

    func testSavePersistsSettingsForNextStoreInstance() {
        let store = ClipSettingsStore(userDefaults: userDefaults)
        let updatedSettings = ClipSettings(secondsBeforeMarker: 6, secondsAfterMarker: 1)

        store.save(updatedSettings)

        XCTAssertEqual(ClipSettingsStore(userDefaults: userDefaults).load(), updatedSettings)
    }

    func testLegacyClipSettingsKeepsDurationsAndAddsDefaultStyle() throws {
        let data = Data(#"{"secondsBeforeMarker":7,"secondsAfterMarker":3}"#.utf8)

        let decoded = try JSONDecoder().decode(ClipSettings.self, from: data)

        XCTAssertEqual(decoded.secondsBeforeMarker, 7)
        XCTAssertEqual(decoded.secondsAfterMarker, 3)
        XCTAssertEqual(decoded.markerLabelStyle, .default)
    }

    func testClipSettingsRoundTripKeepsMarkerLabelStyle() throws {
        let settings = ClipSettings(
            secondsBeforeMarker: 6,
            secondsAfterMarker: 2,
            markerLabelStyle: MarkerLabelStyle(
                fontSizeRatio: 0.14,
                normalizedCenterX: 0.7,
                normalizedCenterY: 0.8,
                textOpacity: 0.65,
                backgroundOpacity: 0.35,
            ),
        )

        let decoded = try JSONDecoder().decode(
            ClipSettings.self,
            from: JSONEncoder().encode(settings),
        )

        XCTAssertEqual(decoded, settings)
    }

    func testStoreSavesAndRestoresNormalizedStyle() {
        let store = ClipSettingsStore(userDefaults: userDefaults)
        let settings = ClipSettings(
            secondsBeforeMarker: 6,
            secondsAfterMarker: 1,
            markerLabelStyle: MarkerLabelStyle(
                fontSizeRatio: 2,
                normalizedCenterX: -1,
                normalizedCenterY: 0.5,
                textOpacity: .nan,
                backgroundOpacity: 0.25,
            ),
        )

        store.save(settings)

        XCTAssertEqual(
            store.load().markerLabelStyle,
            MarkerLabelStyle(
                fontSizeRatio: 0.16,
                normalizedCenterX: 0,
                normalizedCenterY: 0.5,
                textOpacity: 1,
                backgroundOpacity: 0.25,
            ),
        )
    }
}
