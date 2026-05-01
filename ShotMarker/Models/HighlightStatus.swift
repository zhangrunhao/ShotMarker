import Foundation

enum HighlightStatus: String, Codable, Equatable {
    case notClipped
    case clipped
    case failed

    var displayName: String {
        switch self {
        case .notClipped:
            return "未剪辑"
        case .clipped:
            return "已剪辑"
        case .failed:
            return "剪辑失败"
        }
    }
}
