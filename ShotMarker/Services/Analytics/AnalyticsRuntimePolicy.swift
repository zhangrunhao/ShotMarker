import Foundation
import StoreKit

nonisolated enum AnalyticsRuntimePolicy {
    static func shouldSend(isDebugBuild: Bool, isPhone: Bool, isSimulator: Bool = false) -> Bool {
        !isDebugBuild && isPhone && !isSimulator
    }

    static var isEnabled: Bool {
        #if DEBUG || targetEnvironment(simulator)
            false
        #else
            true
        #endif
    }
}

nonisolated enum AnalyticsDistribution: String, Sendable {
    case appStore = "app_store"
    case test, unknown

    static func classify(hasProvisioningProfile: Bool, isSandboxReceipt: Bool,
        verifiedEnvironment: String?, bundleMatches: Bool) -> Self {
        if hasProvisioningProfile || isSandboxReceipt { return .test }
        guard bundleMatches else { return .unknown }
        switch verifiedEnvironment {
        case "Production": return .appStore
        case "Sandbox", "Xcode": return .test
        default: return .unknown
        }
    }

    static func current() async -> Self {
        let bundle = Bundle.main
        let hasProfile = bundle.url(forResource: "embedded", withExtension: "mobileprovision") != nil
        let sandbox = bundle.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        if hasProfile || sandbox { return .test }
        do {
            guard case let .verified(transaction) = try await AppTransaction.shared else { return .unknown }
            return classify(hasProvisioningProfile: false, isSandboxReceipt: false,
                verifiedEnvironment: transaction.environment.rawValue,
                bundleMatches: transaction.bundleID == bundle.bundleIdentifier)
        } catch { return .unknown }
    }
}

nonisolated enum AnalyticsPreferences {
    static let selfUseKey = "analytics.is_self_use"
}
