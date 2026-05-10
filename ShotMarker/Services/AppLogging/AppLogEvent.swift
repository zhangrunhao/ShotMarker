import Foundation

nonisolated enum AppLogLevel: String, Codable, Equatable, Sendable {
    case debug
    case info
    case warning
    case error
}

nonisolated enum AppLogCategory: String, Codable, Equatable, Sendable {
    case app
    case training
    case sync
    case video
    case photos
    case diagnostics
}

nonisolated struct AppLogEvent: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let level: AppLogLevel
    let category: AppLogCategory
    let name: String
    let message: String
    let context: [String: String]
    let errorDomain: String?
    let errorCode: Int?
    let errorDescription: String?

    static func make(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: AppLogLevel,
        category: AppLogCategory,
        name: String,
        message: String,
        context: [String: String] = [:],
        error: Error? = nil,
    ) -> AppLogEvent {
        let nsError = error as NSError?

        return AppLogEvent(
            id: id,
            timestamp: timestamp,
            level: level,
            category: category,
            name: name,
            message: message,
            context: context,
            errorDomain: nsError?.domain,
            errorCode: nsError?.code,
            errorDescription: nsError?.localizedDescription,
        )
    }
}
