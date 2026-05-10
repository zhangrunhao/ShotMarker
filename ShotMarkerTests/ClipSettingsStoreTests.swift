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

    func testDefaultClipSettingsUseFiveSecondsBeforeAndTwoSecondsAfterMarker() {
        XCTAssertEqual(ClipSettings.default, ClipSettings(secondsBeforeMarker: 5, secondsAfterMarker: 2))
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
}
