import Foundation

struct ClipSettings: Codable, Equatable {
    var secondsBeforeMarker: TimeInterval
    var secondsAfterMarker: TimeInterval

    static let `default` = ClipSettings(secondsBeforeMarker: 9, secondsAfterMarker: 4)
}

struct ClipSettingsStore {
    static let shared = ClipSettingsStore()

    private let userDefaults: UserDefaults
    private let key: String

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "ShotMarker.clipSettings",
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    func load() -> ClipSettings {
        guard let data = userDefaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(ClipSettings.self, from: data)
        else {
            return .default
        }

        return settings
    }

    func save(_ settings: ClipSettings) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }

        userDefaults.set(data, forKey: key)
    }
}
