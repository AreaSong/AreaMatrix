import Foundation

struct ObservabilityRecoveryNotice: Equatable {
    let incidentID: String
}

struct ObservabilityStopFailure: Equatable {
    let stage: ObservabilityStopReport.Stage
    let code: String
}

struct ObservabilityStopReport: Equatable {
    enum Stage: String, Equatable {
        case acceptedMutations
        case coreProducerGate
        case coreFlush
        case adapterDrain
        case hubFlush
        case storeClose
        case sessionMarker
    }

    var completedStages: [Stage] = []
    var failures: [ObservabilityStopFailure] = []
    var timedOut = false
    var cleanSessionMarkerWritten = false

    var succeeded: Bool {
        !timedOut && failures.isEmpty && cleanSessionMarkerWritten
    }
}

enum ObservabilityRuntimeError: Error, Equatable {
    case notRunning
}

extension ObservabilityRuntimeAssembly {
    enum State: String, Equatable {
        case idle
        case starting
        case running
        case stopping
        case stopped
    }

    func sessionIDSnapshot() -> String {
        sessionID
    }
}

struct ObservabilityRuntimeScheduler {
    let nowMilliseconds: @Sendable () -> Int64
    let nowUptimeNanoseconds: @Sendable () -> UInt64
    let sleep: @Sendable (Duration) async throws -> Void

    static let live = Self(
        nowMilliseconds: { ObservabilityTime.milliseconds(Date()) },
        nowUptimeNanoseconds: { DispatchTime.now().uptimeNanoseconds },
        sleep: { try await Task.sleep(for: $0) }
    )
}

enum ObservabilityRuntimePolicy {
    static func coreConfiguration(
        _ configuration: AppObservabilityConfiguration,
        sessionID: String
    ) -> ObservabilityConfig {
        ObservabilityConfig(
            sessionId: sessionID,
            mode: configuration.mode.coreMode,
            minimumSeverity: configuration.minimumSeverity.coreSeverity,
            queueCapacity: 4096,
            includeSensitive: configuration.includeSensitive
        )
    }

    static func normalizedLease(
        _ configuration: AppObservabilityConfiguration
    ) -> AppObservabilityConfiguration {
        guard configuration.mode.supportsExpiry else {
            var normalized = configuration
            normalized.modeLease = nil
            return normalized
        }
        return configuration
    }

    static func stableErrorCode(_ error: Error) -> String {
        if let error = error as? ObservabilityStoreError {
            return "store-\(String(describing: error))"
        }
        if let error = error as? ObservabilitySafeFileError {
            return "file-\(String(describing: error))"
        }
        return "operation-failed"
    }

    static func saturatingAdd(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? .max : value
    }

    static func saturatingMultiply(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let (value, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        return overflow ? .max : value
    }

    static func delayMilliseconds(until expiry: Int64, now: Int64) -> Int64 {
        guard expiry > now else { return 0 }
        let (value, overflow) = expiry.subtractingReportingOverflow(now)
        return overflow ? .max : value
    }
}

final class ObservabilityStopRaceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resolved = false

    @discardableResult
    func resolve(
        _ report: ObservabilityStopReport,
        continuation: CheckedContinuation<ObservabilityStopReport, Never>
    ) -> Bool {
        lock.lock()
        guard !resolved else {
            lock.unlock()
            return false
        }
        resolved = true
        lock.unlock()
        continuation.resume(returning: report)
        return true
    }
}

extension Duration {
    var clampedMilliseconds: Int64 {
        let components = components
        let seconds = max(0, components.seconds)
        let attoseconds = max(0, components.attoseconds)
        let whole = seconds.multipliedReportingOverflow(by: 1000)
        guard !whole.overflow else { return .max }
        let fractional = attoseconds / 1_000_000_000_000_000
        let (value, overflow) = whole.partialValue.addingReportingOverflow(fractional)
        return overflow ? .max : value
    }
}
