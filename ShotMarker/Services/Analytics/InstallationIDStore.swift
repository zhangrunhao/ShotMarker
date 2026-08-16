import Foundation

nonisolated protocol InstallationIDProviding: Sendable {
    func installationID() -> String
}

nonisolated final class InstallationIDStore: InstallationIDProviding, @unchecked Sendable {
    static let shared = InstallationIDStore()
    static let storageKey = "analytics.installation_id"

    private let userDefaults: UserDefaults
    private let makeID: @Sendable () -> String
    private let lock = NSLock()

    init(
        userDefaults: UserDefaults = .standard,
        makeID: @Sendable @escaping () -> String = InstallationIDStore.makeRandomID,
    ) {
        self.userDefaults = userDefaults
        self.makeID = makeID
    }

    func installationID() -> String {
        lock.withLock {
            if let stored = userDefaults.string(forKey: Self.storageKey),
               Self.isValid(stored)
            {
                return stored
            }

            let generated = makeID()
            precondition(
                Self.isValid(generated),
                "Installation ID generator must return 12 alphanumeric characters",
            )
            userDefaults.set(generated, forKey: Self.storageKey)
            return generated
        }
    }

    static func isValid(_ value: String) -> Bool {
        guard value.utf8.count == 12 else {
            return false
        }

        return value.utf8.allSatisfy { byte in
            (48 ... 57).contains(byte)
                || (65 ... 90).contains(byte)
                || (97 ... 122).contains(byte)
        }
    }

    static func makeRandomID() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12))
    }
}
