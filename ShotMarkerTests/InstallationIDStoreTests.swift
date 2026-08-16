@testable import ShotMarker
import Foundation
import XCTest

final class InstallationIDStoreTests: XCTestCase {
    private var suiteName: String!
    private var userDefaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "ShotMarker.InstallationIDStoreTests.\(UUID().uuidString)"
        userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        suiteName = nil
    }

    func testFirstReadGeneratesAndPersistsTwelveCharacterIdentifier() {
        let store = InstallationIDStore(
            userDefaults: userDefaults,
            makeID: { "AbCd1234Ef56" },
        )

        XCTAssertEqual(store.installationID(), "AbCd1234Ef56")
        XCTAssertEqual(
            userDefaults.string(forKey: InstallationIDStore.storageKey),
            "AbCd1234Ef56",
        )
    }

    func testLaterStoreInstancesReuseThePersistedIdentifier() {
        userDefaults.set("Reuse1234AbC", forKey: InstallationIDStore.storageKey)
        let store = InstallationIDStore(
            userDefaults: userDefaults,
            makeID: { "Other1234AbC" },
        )

        XCTAssertEqual(store.installationID(), "Reuse1234AbC")
    }

    func testMalformedStoredValueIsReplaced() {
        userDefaults.set("not-valid", forKey: InstallationIDStore.storageKey)
        let store = InstallationIDStore(
            userDefaults: userDefaults,
            makeID: { "Valid1234AbC" },
        )

        XCTAssertEqual(store.installationID(), "Valid1234AbC")
        XCTAssertEqual(
            userDefaults.string(forKey: InstallationIDStore.storageKey),
            "Valid1234AbC",
        )
    }

    func testDefaultGeneratorProducesTwelveAlphanumericCharacters() {
        let value = InstallationIDStore(userDefaults: userDefaults).installationID()

        XCTAssertTrue(InstallationIDStore.isValid(value))
        XCTAssertEqual(value.utf8.count, 12)
    }
}
