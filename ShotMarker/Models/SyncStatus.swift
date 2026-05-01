import Foundation

enum SyncStatus: String, Codable, Equatable {
    case pending
    case synced
    case failed

    var displayName: String {
        switch self {
        case .pending:
            return "待同步"
        case .synced:
            return "已同步"
        case .failed:
            return "同步失败"
        }
    }
}
