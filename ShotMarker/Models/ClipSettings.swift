import Foundation

struct ClipSettings: Codable, Equatable {
    var secondsBeforeMarker: TimeInterval
    var secondsAfterMarker: TimeInterval

    static let `default` = ClipSettings(secondsBeforeMarker: 10, secondsAfterMarker: 3)
}
