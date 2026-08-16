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

    func testConcurrentFirstAccessGeneratesOnceAndPersistsOneIdentifier() async {
        let generator = ConcurrentIDGenerator()
        let store = InstallationIDStore(
            userDefaults: userDefaults,
            makeID: { generator.makeID() },
        )

        let values = await withTaskGroup(of: String.self, returning: [String].self) { group in
            for _ in 0 ..< 32 {
                group.addTask {
                    store.installationID()
                }
            }

            var values: [String] = []
            for await value in group {
                values.append(value)
            }
            return values
        }

        XCTAssertEqual(Set(values), Set(["ID0000000001"]))
        XCTAssertEqual(generator.callCount, 1)
        XCTAssertEqual(
            userDefaults.string(forKey: InstallationIDStore.storageKey),
            "ID0000000001",
        )
    }

    func testStoredIdentifierWithWrongLengthIsReplaced() {
        userDefaults.set("AbCd1234Ef5", forKey: InstallationIDStore.storageKey)
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

    func testStoredIdentifierWithIllegalCharacterIsReplaced() {
        userDefaults.set("AbCd1234Ef5_", forKey: InstallationIDStore.storageKey)
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

    func testDefaultGeneratorProducesTwelveASCIIAlphanumericCharacters() {
        let value = InstallationIDStore.makeRandomID()

        XCTAssertEqual(value.utf8.count, 12)
        XCTAssertTrue(
            value.utf8.allSatisfy { byte in
                (48 ... 57).contains(byte)
                    || (65 ... 90).contains(byte)
                    || (97 ... 122).contains(byte)
            },
        )
    }
}

private final class ConcurrentIDGenerator: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var callCount: Int {
        lock.withLock { count }
    }

    func makeID() -> String {
        let callNumber = lock.withLock {
            count += 1
            return count
        }
        Thread.sleep(forTimeInterval: 0.02)
        return String(format: "ID%010d", callNumber)
    }
}
