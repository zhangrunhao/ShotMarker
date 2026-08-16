import Foundation

nonisolated enum AnalyticsRuntimePolicy {
    static func shouldSend(isDebugBuild: Bool, isPhone: Bool) -> Bool {
        !isDebugBuild && isPhone
    }
}
