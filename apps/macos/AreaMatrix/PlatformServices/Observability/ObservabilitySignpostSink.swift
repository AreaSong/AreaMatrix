import Foundation
import OSLog

enum ObservabilitySignpostRegistration: String, CaseIterable {
    case importOperation = "repository.import.operation"
    case importValidation = "repository.import.validation"
    case importStaging = "repository.import.staging"
    case importFingerprint = "repository.import.fingerprint"
    case importDuplicateResolution = "repository.import.duplicate_resolution"
    case importDestination = "repository.import.destination"
    case importStagingDatabaseRow = "repository.import.staging_db_row"
    case importFilesystemCommit = "repository.import.filesystem_commit"
    case importDatabasePromotion = "repository.import.db_promotion"
    case importOverview = "repository.import.overview"
    case importSourceRemoval = "repository.import.source_removal"
}

struct ObservabilitySignpostHealth: Equatable {
    var activeIntervalCount: Int
    var rejectedIntervalCount: UInt64
}

struct ObservabilitySignpostCorrelation: Equatable {
    let registration: ObservabilitySignpostRegistration
    let category: String
    let spanID: String
    let correlationKey: String
}

private struct ObservabilitySignpostStageRegistration {
    let actionID: String
    let componentID: String
    let registration: ObservabilitySignpostRegistration
}

protocol ObservabilitySignpostRecording: Sendable {
    func begin(_ registration: ObservabilitySignpostRegistration, key: String)
    func end(_ registration: ObservabilitySignpostRegistration, key: String)
}

final class ObservabilitySignpostSink: @unchecked Sendable {
    static let instrumentsCategory = "RegisteredPerformance"

    private struct Pair: Hashable {
        let actionID: String
        let componentID: String
    }

    private let lock = NSLock()
    private let recorder: any ObservabilitySignpostRecording
    private let maximumActiveIntervals: Int
    private var active: [String: ObservabilitySignpostRegistration] = [:]
    private var rejected: UInt64 = 0

    init(
        recorder: any ObservabilitySignpostRecording = SystemObservabilitySignpostRecorder(),
        maximumActiveIntervals: Int = 1024
    ) {
        self.recorder = recorder
        self.maximumActiveIntervals = max(1, maximumActiveIntervals)
    }

    func consume(_ event: ObservabilityEventSnapshot) {
        guard let correlation = Self.correlation(for: event) else { return }
        switch event.phase {
        case "started": begin(correlation.registration, key: correlation.correlationKey)
        case "completed": end(correlation.registration, key: correlation.correlationKey)
        default: break
        }
    }

    static func correlation(for event: ObservabilityEventSnapshot) -> ObservabilitySignpostCorrelation? {
        guard let registration = allowlist[Pair(
            actionID: event.actionID,
            componentID: event.componentID
        )] else { return nil }
        return ObservabilitySignpostCorrelation(
            registration: registration,
            category: instrumentsCategory,
            spanID: event.spanID,
            correlationKey: "\(event.sessionID):\(event.spanID):\(registration.rawValue)"
        )
    }

    func health() -> ObservabilitySignpostHealth {
        lock.withObservabilityLock {
            ObservabilitySignpostHealth(
                activeIntervalCount: active.count,
                rejectedIntervalCount: rejected
            )
        }
    }

    func reset() {
        let intervals = lock.withObservabilityLock { () -> [String: ObservabilitySignpostRegistration] in
            let intervals = active
            active.removeAll(keepingCapacity: true)
            return intervals
        }
        for (key, registration) in intervals {
            recorder.end(registration, key: key)
        }
    }
}

private extension ObservabilitySignpostSink {
    private static let allowlist: [Pair: ObservabilitySignpostRegistration] = {
        var pairs: [Pair: ObservabilitySignpostRegistration] = [:]
        let rootActionIDs = [
            "repository.import.confirmed",
            "repository.import.single.confirmed",
            "repository.import.retry.confirmed"
        ]
        for rootActionID in rootActionIDs {
            pairs[Pair(actionID: rootActionID, componentID: "core.repository.import")] = .importOperation
        }
        let stages = [
            ObservabilitySignpostStageRegistration(
                actionID: "repository.import.validation",
                componentID: "core.storage.import",
                registration: .importValidation
            ),
            ObservabilitySignpostStageRegistration(
                actionID: "repository.import.staging",
                componentID: "core.storage.import",
                registration: .importStaging
            ),
            ObservabilitySignpostStageRegistration(
                actionID: "repository.import.fingerprint",
                componentID: "core.storage.import",
                registration: .importFingerprint
            ),
            ObservabilitySignpostStageRegistration(
                actionID: "repository.import.duplicate_resolution",
                componentID: "core.storage.dedup",
                registration: .importDuplicateResolution
            ),
            ObservabilitySignpostStageRegistration(
                actionID: "repository.import.destination",
                componentID: "core.storage.import",
                registration: .importDestination
            ),
            ObservabilitySignpostStageRegistration(
                actionID: "repository.import.staging_db_row",
                componentID: "core.storage.import",
                registration: .importStagingDatabaseRow
            ),
            ObservabilitySignpostStageRegistration(
                actionID: "repository.import.filesystem_commit",
                componentID: "core.storage.import",
                registration: .importFilesystemCommit
            ),
            ObservabilitySignpostStageRegistration(
                actionID: "repository.import.db_promotion",
                componentID: "core.storage.import",
                registration: .importDatabasePromotion
            ),
            ObservabilitySignpostStageRegistration(
                actionID: "repository.import.overview",
                componentID: "core.storage.overview",
                registration: .importOverview
            ),
            ObservabilitySignpostStageRegistration(
                actionID: "repository.import.source_removal",
                componentID: "core.storage.import",
                registration: .importSourceRemoval
            )
        ]
        for stage in stages {
            pairs[Pair(actionID: stage.actionID, componentID: stage.componentID)] = stage.registration
        }
        return pairs
    }()

    func begin(_ registration: ObservabilitySignpostRegistration, key: String) {
        lock.withObservabilityLock {
            guard active[key] == nil, active.count < maximumActiveIntervals else {
                incrementRejected()
                return
            }
            active[key] = registration
            recorder.begin(registration, key: key)
        }
    }

    func end(_ registration: ObservabilitySignpostRegistration, key: String) {
        lock.withObservabilityLock {
            guard active.removeValue(forKey: key) == registration else {
                incrementRejected()
                return
            }
            recorder.end(registration, key: key)
        }
    }

    func incrementRejected() {
        if rejected < .max { rejected += 1 }
    }
}

final class SystemObservabilitySignpostRecorder: ObservabilitySignpostRecording, @unchecked Sendable {
    private static let intervalNames: [ObservabilitySignpostRegistration: StaticString] = [
        .importOperation: "Repository Import",
        .importValidation: "Import Validation",
        .importStaging: "Import Staging",
        .importFingerprint: "Import Fingerprint",
        .importDuplicateResolution: "Import Duplicate Resolution",
        .importDestination: "Import Destination",
        .importStagingDatabaseRow: "Import Staging Database Row",
        .importFilesystemCommit: "Import Filesystem Commit",
        .importDatabasePromotion: "Import Database Promotion",
        .importOverview: "Import Overview",
        .importSourceRemoval: "Import Source Removal"
    ]

    private let lock = NSLock()
    private let signposter = OSSignposter(
        subsystem: "app.areamatrix.AreaMatrix",
        category: ObservabilitySignpostSink.instrumentsCategory
    )
    private var states: [String: OSSignpostIntervalState] = [:]

    func begin(_ registration: ObservabilitySignpostRegistration, key: String) {
        lock.withObservabilityLock {
            guard let name = Self.intervalNames[registration] else { return }
            states[key] = signposter.beginInterval(name)
        }
    }

    func end(_ registration: ObservabilitySignpostRegistration, key: String) {
        lock.withObservabilityLock {
            guard let state = states.removeValue(forKey: key),
                  let name = Self.intervalNames[registration]
            else { return }
            signposter.endInterval(name, state)
        }
    }
}

struct ObservabilitySystemLogSink {
    private let logger = Logger(
        subsystem: "app.areamatrix.AreaMatrix",
        category: "Observability"
    )

    func consume(_ event: ObservabilityEventSnapshot) {
        let line = "action=\(event.actionID) component=\(event.componentID) phase=\(event.phase) "
            + "outcome=\(event.outcome) trace=\(event.traceID)"
        switch event.severity {
        case .trace, .debug: logger.debug("\(line, privacy: .public)")
        case .info: logger.info("\(line, privacy: .public)")
        case .warn: logger.warning("\(line, privacy: .public)")
        case .error: logger.error("\(line, privacy: .public)")
        }
    }
}

private extension NSLock {
    func withObservabilityLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
