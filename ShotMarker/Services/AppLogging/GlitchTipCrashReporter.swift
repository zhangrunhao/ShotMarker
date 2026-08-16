import Foundation
import Sentry

nonisolated protocol AppErrorReporting: Sendable {
    func report(_ event: AppLogEvent)
}

nonisolated struct NoopAppErrorReporter: AppErrorReporting {
    func report(_ event: AppLogEvent) {}
}

nonisolated final class GlitchTipErrorReporter: AppErrorReporting, @unchecked Sendable {
    static let shared = GlitchTipErrorReporter()

    private init() {}

    func report(_ event: AppLogEvent) {
        guard SentrySDK.isEnabled else {
            return
        }

        SentrySDK.capture(event: Self.makeRemoteEvent(from: event))
    }

    static func makeRemoteEvent(from event: AppLogEvent) -> Event {
        let remoteEvent = Event(level: .error)
        remoteEvent.timestamp = event.timestamp
        remoteEvent.message = SentryMessage(formatted: event.message)
        remoteEvent.logger = "ShotMarker.AppLogger"

        var tags = [
            "app.error.name": event.name,
            "app.error.category": event.category.rawValue,
        ]
        var fingerprint = [event.name]

        if let errorDomain = event.errorDomain {
            tags["error.domain"] = errorDomain
            fingerprint.append(errorDomain)
        }
        if let errorCode = event.errorCode {
            let errorCode = String(errorCode)
            tags["error.code"] = errorCode
            fingerprint.append(errorCode)
        }

        remoteEvent.tags = tags
        remoteEvent.fingerprint = fingerprint
        return remoteEvent
    }
}

nonisolated struct GlitchTipConfiguration: Equatable, Sendable {
    static let infoDictionaryKey = "GLITCHTIP_DSN"
    static let expectedHost = "glitchtip.zhangrh.shop"

    let dsn: String
    let environment: String

    static func load(
        infoDictionary: [String: Any],
        environment: String = buildEnvironment,
    ) -> GlitchTipConfiguration? {
        guard let rawDSN = infoDictionary[infoDictionaryKey] as? String else {
            return nil
        }

        let dsn = rawDSN.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let components = URLComponents(string: dsn),
            components.scheme == "https",
            components.host == expectedHost,
            components.user?.isEmpty == false,
            components.path.split(separator: "/").count == 1
        else {
            return nil
        }

        return GlitchTipConfiguration(dsn: dsn, environment: environment)
    }

    private static var buildEnvironment: String {
        #if DEBUG
            "development"
        #else
            "production"
        #endif
    }
}

@MainActor
enum GlitchTipCrashReporter {
    @discardableResult
    static func start(infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]) -> Bool {
        guard let configuration = GlitchTipConfiguration.load(infoDictionary: infoDictionary) else {
            return false
        }

        SentrySDK.start { options in
            options.dsn = configuration.dsn
            options.environment = configuration.environment
            options.sampleRate = 1
            options.sendDefaultPii = false
            options.attachStacktrace = true
            options.enableAutoSessionTracking = false

            options.tracesSampleRate = 0
            options.enableAutoPerformanceTracing = false
            options.enableUIViewControllerTracing = false
            options.enableUserInteractionTracing = false
            options.enableNetworkTracking = false
            options.enableFileIOTracing = false
            options.enableCoreDataTracing = false
            options.enableMetrics = false

            options.enableAppHangTracking = false
            options.enableWatchdogTerminationTracking = false
            options.enableCaptureFailedRequests = false
            options.enableAutoBreadcrumbTracking = false
            options.enableNetworkBreadcrumbs = false

            #if os(iOS)
                options.sessionReplay.sessionSampleRate = 0
                options.sessionReplay.onErrorSampleRate = 0
            #endif
        }

        return true
    }
}
