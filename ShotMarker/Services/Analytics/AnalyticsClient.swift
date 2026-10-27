import Foundation

nonisolated final class AnalyticsClient: AnalyticsTracking, @unchecked Sendable {
    typealias RequestSender = @Sendable (URLRequest) async -> Void

    static let productionEndpoint = URL(string: "https://zhangrh.shop/track")!

    private let endpoint: URL
    private let installationIDProvider: InstallationIDProviding
    private let sendRequest: RequestSender
    private let resolveDistribution: (@Sendable () async -> AnalyticsDistribution)?
    private let audienceLock = NSLock()
    private var audiences: [UUID: Audience] = [:]
    private var finishedOperations: [UUID] = []
    private let distribution: @Sendable () -> AnalyticsDistribution
    private let userDefaults: UserDefaults
    private let version: String
    private let build: String

    init(
        endpoint: URL = AnalyticsClient.productionEndpoint,
        installationIDProvider: InstallationIDProviding = InstallationIDStore.shared,
        distribution: @escaping @Sendable () -> AnalyticsDistribution = { .unknown },
        resolveDistribution: (@Sendable () async -> AnalyticsDistribution)? = nil,
        userDefaults: UserDefaults = .standard,
        appVersion: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
        appBuild: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
        sendRequest: @escaping RequestSender,
    ) {
        self.endpoint = endpoint
        self.installationIDProvider = installationIDProvider
        self.sendRequest = sendRequest
        self.distribution = distribution
        self.resolveDistribution = resolveDistribution
        self.userDefaults = userDefaults
        version = Self.validatedVersion(appVersion, allowsDots: true)
        build = Self.validatedVersion(appBuild, allowsDots: false)
    }

    func track(_ event: AnalyticsEvent) {
        dispatch(event, operationID: nil, stage: nil, reason: nil)
    }

    func track(_ event: AnalyticsEvent, operationID: UUID, stage: AnalyticsStage, reason: AnalyticsReason?) {
        dispatch(event, operationID: operationID, stage: stage, reason: reason)
    }

    private func dispatch(_ event: AnalyticsEvent, operationID: UUID?, stage: AnalyticsStage?, reason: AnalyticsReason?) {
        let audience = audience(for: operationID, event: event)
        finishAudience(operationID, event: event)
        Task {
            let source = await resolveDistribution?() ?? distribution()
            guard let request = makeRequest(for: event, operationID: operationID, stage: stage,
                reason: reason, audience: audience, source: source) else { return }
            await sendRequest(request)
        }
    }

    func makeRequest(for event: AnalyticsEvent, operationID: UUID? = nil,
        stage: AnalyticsStage? = nil, reason: AnalyticsReason? = nil) -> URLRequest? {
        makeRequest(for: event, operationID: operationID, stage: stage, reason: reason,
            audience: audience(for: operationID, event: event), source: distribution())
    }

    private func makeRequest(for event: AnalyticsEvent, operationID: UUID?, stage: AnalyticsStage?,
        reason: AnalyticsReason?, audience: Audience, source: AnalyticsDistribution) -> URLRequest? {
        let source = audience.source(resolvingTo: source)
        guard var components = URLComponents(
            url: endpoint,
            resolvingAgainstBaseURL: false,
        ) else {
            return nil
        }

        components.queryItems = [
            URLQueryItem(name: "project", value: "shotmarker"),
            URLQueryItem(name: "event", value: event.rawValue),
            URLQueryItem(name: "device_id", value: installationIDProvider.installationID()),
            URLQueryItem(name: "distribution", value: source.rawValue),
            URLQueryItem(name: "is_self_use", value: audience.isSelfUse ? "true" : "false"),
            URLQueryItem(name: "app_version", value: version),
            URLQueryItem(name: "app_build", value: build),
        ]

        if event != .appLaunch {
            if let operationID { components.queryItems?.append(URLQueryItem(name: "operation_id", value: operationID.uuidString.lowercased())) }
            if let stage { components.queryItems?.append(URLQueryItem(name: "stage", value: stage.rawValue)) }
            if let reason { components.queryItems?.append(URLQueryItem(name: "reason", value: reason.rawValue)) }
        }
        guard let url = components.url else {
            return nil
        }

        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 5,
        )
        request.httpMethod = "GET"
        return request
    }

    private func audience(for operationID: UUID?, event: AnalyticsEvent) -> Audience {
        audienceLock.withLock {
            guard event != .appLaunch, let operationID else {
                return Audience(isSelfUse: userDefaults.bool(forKey: AnalyticsPreferences.selfUseKey))
            }
            if let existing = audiences[operationID] { return existing }
            let audience = Audience(isSelfUse: userDefaults.bool(forKey: AnalyticsPreferences.selfUseKey))
            audiences[operationID] = audience
            // Completed operations remain briefly available for ACK/local-state diagnostics.
            // Active operations are never evicted while their result is pending.
            return audience
        }
    }

    private func finishAudience(_ operationID: UUID?, event: AnalyticsEvent) {
        guard let operationID, [AnalyticsEvent.trainingSyncSucceeded, .trainingSyncFailed, .trainingSyncIgnored,
            .highlightGenerateSucceeded, .highlightGenerateFailed, .highlightGenerateCancelled,
            .highlightSaveSucceeded, .highlightSaveFailed, .highlightSaveCancelled].contains(event) else { return }
        audienceLock.withLock {
            guard !finishedOperations.contains(operationID) else { return }
            finishedOperations.append(operationID)
            if finishedOperations.count > 512 { audiences.removeValue(forKey: finishedOperations.removeFirst()) }
        }
    }

    private final class Audience: @unchecked Sendable {
        let isSelfUse: Bool
        private let lock = NSLock()
        private var distribution: AnalyticsDistribution?
        init(isSelfUse: Bool) { self.isSelfUse = isSelfUse }
        func source(resolvingTo value: AnalyticsDistribution) -> AnalyticsDistribution {
            lock.withLock {
                if let distribution { return distribution }
                distribution = value
                return value
            }
        }
    }

    private static func validatedVersion(_ value: String?, allowsDots: Bool) -> String {
        guard let value, !value.isEmpty, value.utf8.count <= 32 else { return "unknown" }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard allowsDots || parts.count == 1,
              parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }) else { return "unknown" }
        return value
    }

    static func live(
        installationIDProvider: InstallationIDProviding = InstallationIDStore.shared,
    ) -> AnalyticsClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)

        let resolution = Task { await AnalyticsDistribution.current() }
        return AnalyticsClient(
            installationIDProvider: installationIDProvider,
            resolveDistribution: { await resolution.value },
            sendRequest: { request in
                do {
                    let (_, response) = try await session.data(for: request)
                    guard let response = response as? HTTPURLResponse,
                          response.statusCode == 204
                    else {
                        return
                    }
                } catch {
                    return
                }
            },
        )
    }
}
