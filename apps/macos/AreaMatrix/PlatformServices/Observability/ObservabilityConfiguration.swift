import Foundation

final class ObservabilityConfigurationStore: @unchecked Sendable {
    private let lock = NSLock()
    private let defaults: UserDefaults?
    private var inMemoryConfiguration: AppObservabilityConfiguration?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        inMemoryConfiguration = nil
    }

    init(inMemory configuration: AppObservabilityConfiguration) {
        defaults = nil
        inMemoryConfiguration = configuration
    }

    func load() -> AppObservabilityConfiguration {
        withLock {
            if let defaults {
                return ObservabilityHubPolicy.loadConfiguration(defaults: defaults)
            }
            return inMemoryConfiguration ?? .standard
        }
    }

    func save(_ configuration: AppObservabilityConfiguration) {
        withLock {
            if let defaults {
                ObservabilityHubPolicy.saveConfiguration(configuration, defaults: defaults)
            } else {
                inMemoryConfiguration = configuration
            }
        }
    }

    private func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}

enum AppObservabilityMode: String, Codable, CaseIterable {
    case disabled
    case standard
    case diagnostic
    case developer

    var persistsToDisk: Bool {
        self != .disabled
    }

    var coreSnapshot: CoreObservabilityModeSnapshot {
        switch self {
        case .disabled: .disabled
        case .standard: .standard
        case .diagnostic: .diagnostic
        case .developer: .developer
        }
    }

    var supportsExpiry: Bool {
        self == .diagnostic || self == .developer
    }

    init(coreSnapshot: CoreObservabilityModeSnapshot) {
        switch coreSnapshot {
        case .disabled: self = .disabled
        case .standard: self = .standard
        case .diagnostic: self = .diagnostic
        case .developer: self = .developer
        }
    }
}

enum AppObservabilityExpiryPolicy: String, Codable, CaseIterable {
    case timed
    case nextLaunch
    case manual
}

struct AppObservabilityModeLease: Codable, Equatable {
    var policy: AppObservabilityExpiryPolicy
    var activatedAtMilliseconds: Int64
    var activationSessionID: String
    var expiresAtMilliseconds: Int64?
}

struct AppObservabilityConfiguration: Codable, Equatable {
    var mode: AppObservabilityMode
    var minimumSeverity: AppObservabilitySeverity
    var diskBudgetBytes: Int64
    var retentionHours: Int
    var includeSensitive: Bool
    var modeLease: AppObservabilityModeLease?

    init(
        mode: AppObservabilityMode,
        minimumSeverity: AppObservabilitySeverity,
        diskBudgetBytes: Int64,
        retentionHours: Int,
        includeSensitive: Bool,
        modeLease: AppObservabilityModeLease? = nil
    ) {
        self.mode = mode
        self.minimumSeverity = minimumSeverity
        self.diskBudgetBytes = diskBudgetBytes
        self.retentionHours = retentionHours
        self.includeSensitive = includeSensitive
        self.modeLease = modeLease
    }

    static let standard = Self(
        mode: .standard,
        minimumSeverity: .info,
        diskBudgetBytes: 50 * 1024 * 1024,
        retentionHours: 7 * 24,
        includeSensitive: false
    )

    func activating(
        policy: AppObservabilityExpiryPolicy,
        durationHours: Int,
        nowMilliseconds: Int64,
        sessionID: String
    ) -> Self {
        var copy = self
        guard mode.supportsExpiry else {
            copy.modeLease = nil
            return copy
        }
        let expiresAt = policy == .timed
            ? nowMilliseconds + Int64(max(1, durationHours)) * 3_600_000
            : nil
        copy.modeLease = AppObservabilityModeLease(
            policy: policy,
            activatedAtMilliseconds: nowMilliseconds,
            activationSessionID: sessionID,
            expiresAtMilliseconds: expiresAt
        )
        return copy
    }
}

enum ObservabilityConfigurationResolver {
    static func resolveForLaunch(
        _ configuration: AppObservabilityConfiguration,
        nowMilliseconds: Int64,
        sessionID: String
    ) -> AppObservabilityConfiguration {
        guard configuration.mode.supportsExpiry else {
            var resolved = configuration
            resolved.modeLease = nil
            return resolved
        }
        guard let lease = configuration.modeLease else {
            return configuration
        }
        switch lease.policy {
        case .manual:
            return configuration
        case .nextLaunch:
            return lease.activationSessionID == sessionID ? configuration : .standard
        case .timed:
            guard let expiry = lease.expiresAtMilliseconds, nowMilliseconds < expiry else {
                return .standard
            }
            return configuration
        }
    }
}
