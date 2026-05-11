import Foundation

nonisolated protocol AppLogging {
    func debug(_ name: String, category: AppLogCategory, message: String, context: [String: String])
    func info(_ name: String, category: AppLogCategory, message: String, context: [String: String])
    func warning(_ name: String, category: AppLogCategory, message: String, context: [String: String])
    func error(
        _ name: String,
        category: AppLogCategory,
        message: String,
        error: Error?,
        context: [String: String],
    )
}

nonisolated final class AppLogger: AppLogging, @unchecked Sendable {
    static let shared = AppLogger(store: AppLogStore.shared)

    private let store: AppLogStore
    private let makeID: @Sendable () -> UUID
    private let now: @Sendable () -> Date

    init(
        store: AppLogStore,
        makeID: @Sendable @escaping () -> UUID = UUID.init,
        now: @Sendable @escaping () -> Date = Date.init,
    ) {
        self.store = store
        self.makeID = makeID
        self.now = now
    }

    func debug(_ name: String, category: AppLogCategory, message: String, context: [String: String] = [:]) {
        log(level: .debug, category: category, name: name, message: message, context: context)
    }

    func info(_ name: String, category: AppLogCategory, message: String, context: [String: String] = [:]) {
        log(level: .info, category: category, name: name, message: message, context: context)
    }

    func warning(_ name: String, category: AppLogCategory, message: String, context: [String: String] = [:]) {
        log(level: .warning, category: category, name: name, message: message, context: context)
    }

    func error(
        _ name: String,
        category: AppLogCategory,
        message: String,
        error: Error? = nil,
        context: [String: String] = [:],
    ) {
        log(level: .error, category: category, name: name, message: message, error: error, context: context)
    }

    private func log(
        level: AppLogLevel,
        category: AppLogCategory,
        name: String,
        message: String,
        error: Error? = nil,
        context: [String: String],
    ) {
        let event = AppLogEvent.make(
            id: makeID(),
            timestamp: now(),
            level: level,
            category: category,
            name: name,
            message: message,
            context: context,
            error: error,
        )
        let store = store

        Task {
            await store.append(event)
        }
    }
}

extension AppLogging {
    func debug(_ name: String, category: AppLogCategory, message: String) {
        debug(name, category: category, message: message, context: [:])
    }

    func info(_ name: String, category: AppLogCategory, message: String) {
        info(name, category: category, message: message, context: [:])
    }

    func warning(_ name: String, category: AppLogCategory, message: String) {
        warning(name, category: category, message: message, context: [:])
    }

    func error(_ name: String, category: AppLogCategory, message: String, error: Error?) {
        self.error(name, category: category, message: message, error: error, context: [:])
    }
}
