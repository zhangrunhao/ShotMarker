import Foundation

nonisolated final class AnalyticsClient: AnalyticsTracking, @unchecked Sendable {
    typealias RequestSender = @Sendable (URLRequest) async -> Void

    static let productionEndpoint = URL(string: "https://zhangrh.shop/track")!

    private let endpoint: URL
    private let installationIDProvider: InstallationIDProviding
    private let sendRequest: RequestSender

    init(
        endpoint: URL = AnalyticsClient.productionEndpoint,
        installationIDProvider: InstallationIDProviding = InstallationIDStore.shared,
        sendRequest: @escaping RequestSender,
    ) {
        self.endpoint = endpoint
        self.installationIDProvider = installationIDProvider
        self.sendRequest = sendRequest
    }

    func track(_ event: AnalyticsEvent) {
        guard let request = makeRequest(for: event) else {
            return
        }

        let sendRequest = sendRequest
        Task {
            await sendRequest(request)
        }
    }

    func makeRequest(for event: AnalyticsEvent) -> URLRequest? {
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
        ]

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

        return AnalyticsClient(
            installationIDProvider: installationIDProvider,
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
