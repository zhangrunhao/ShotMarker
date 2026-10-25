import Combine
import SwiftUI

@MainActor
protocol ShotMarkerServiceLifecycle: AnyObject {
    func load() async
    func start()
    func enterBackground()
    func enterForeground()
}

@MainActor
final class ShotMarkerBootstrap<Services: ShotMarkerServiceLifecycle>: ObservableObject {
    @Published private(set) var services: Services?
    @Published private(set) var resetFailed = false
    private var starting = false
    private var isForeground = true
    private let reset: @MainActor () throws -> Date?
    private let makeServices: @MainActor (Date?) -> Services

    init(
        reset: @escaping @MainActor () throws -> Date? = {
            try AppDataResetCoordinator.live(platform: .phone).resetIfNeeded()
        },
        makeServices: @escaping @MainActor (Date?) -> Services,
    ) {
        self.reset = reset
        self.makeServices = makeServices
    }

    func updateScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            isForeground = false
            services?.enterBackground()
        case .active:
            isForeground = true
            services?.enterForeground()
        default:
            break
        }
    }

    func start() async {
        guard services == nil, !starting else { return }
        starting = true
        defer { starting = false }
        do {
            let cutover = try reset()
            let ready = makeServices(cutover)
            await ready.load()
            if isForeground {
                ready.enterForeground()
            } else {
                ready.enterBackground()
            }
            ready.start()
            services = ready
            resetFailed = false
        } catch { resetFailed = true }
    }
}

extension ShotMarkerBootstrap where Services == ShotMarkerServices {
    convenience init() {
        self.init(makeServices: ShotMarkerServices.init)
    }
}
