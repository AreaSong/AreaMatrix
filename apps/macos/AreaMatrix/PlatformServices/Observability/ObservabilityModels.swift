import Foundation

enum ObservabilityProcessIdentity {
    static let sessionID = UUID().uuidString.lowercased()
}

struct ObservabilityBuildContextSnapshot: Equatable {
    var producer: String
    var version: String
    var build: String?
    var configuration: String
    var platform: String
    var architecture: String

    static let currentApp = Self(
        producer: "areamatrix_macos",
        version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0",
        build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
        configuration: {
            #if DEBUG
            "debug"
            #else
            "release"
            #endif
        }(),
        platform: "macos",
        architecture: {
            #if arch(arm64)
            "arm64"
            #elseif arch(x86_64)
            "x86_64"
            #else
            "unknown"
            #endif
        }()
    )
}

enum AppObservabilitySeverity: String, Codable, CaseIterable {
    case trace, debug, info, warn, error

    var coreSeverity: ObservabilitySeverity {
        switch self {
        case .trace: .trace
        case .debug: .debug
        case .info: .info
        case .warn: .warn
        case .error: .error
        }
    }

    var rank: Int {
        switch self {
        case .trace: 0
        case .debug: 1
        case .info: 2
        case .warn: 3
        case .error: 4
        }
    }
}

struct ObservabilityAttributeSnapshot: Equatable {
    var key: String
    var value: String
    var privacy: String
}

struct ObservabilityResourceSnapshot: Equatable {
    var resourceID: String
    var alias: String
    var pathExtension: String?
    var sizeBucket: String?
    var storageMode: String?
}

struct ObservabilityErrorSnapshot: Equatable {
    var code: String
    var kind: String?
    var technicalDetails: String?
}

struct ObservabilitySemanticEventInput {
    var actionID: String
    var componentID: String
    var traceID = UUID().uuidString.lowercased()
    var spanID = UUID().uuidString.lowercased()
    var parentSpanID: String?
    var incidentID: String?
    var operationID: String?
    var retryOfOperationID: String?
    var layer = "swift_ui"
    var phase = "event"
    var severity = AppObservabilitySeverity.info
    var outcome = "none"
    var durationMilliseconds: UInt64?
    var resources: [ObservabilityResourceSnapshot] = []
    var error: ObservabilityErrorSnapshot?
    var attributes: [ObservabilityAttributeSnapshot] = []
    var privacy: String?
    var message: String?
    var target: String?

    var resolvedPrivacy: String {
        if let privacy { return privacy }
        var rank = resources.isEmpty ? 0 : 1
        for attribute in attributes {
            rank = max(rank, Self.privacyRank(attribute.privacy))
        }
        if error?.technicalDetails != nil { rank = max(rank, 2) }
        return ["public", "pseudonymous", "sensitive", "prohibited"][min(rank, 3)]
    }

    private static func privacyRank(_ value: String) -> Int {
        switch value {
        case "public": 0
        case "pseudonymous": 1
        case "sensitive": 2
        case "prohibited": 3
        default: 3
        }
    }
}

struct ObservabilityEventSnapshot: Equatable, Identifiable {
    var id: String {
        eventID
    }

    var schemaVersion: UInt64
    var eventID: String
    var wallTimestampMilliseconds: Int64
    var monotonicTimestampNanoseconds: UInt64
    var sequenceNumber: UInt64
    var sessionID: String
    var incidentID: String?
    var traceID: String
    var spanID: String
    var parentSpanID: String?
    var operationID: String?
    var retryOfOperationID: String?
    var actionID: String
    var componentID: String
    var layer: String
    var phase: String
    var severity: AppObservabilitySeverity
    var outcome: String
    var durationMilliseconds: UInt64?
    var resources: [ObservabilityResourceSnapshot]
    var error: ObservabilityErrorSnapshot?
    var attributes: [ObservabilityAttributeSnapshot]
    var privacy: String
    var message: String?
    var target: String?
    var threadName: String?
    var buildContext: ObservabilityBuildContextSnapshot?
}

enum ObservabilityIncidentStatus: String, Codable, CaseIterable {
    case open
    case resolved
    case dismissed
}

struct ObservabilityIncidentSnapshot: Codable, Equatable, Identifiable {
    var id: String
    var sessionID: String
    var markedAtMilliseconds: Int64
    var captureEndsAtMilliseconds: Int64
    var status: ObservabilityIncidentStatus
    var note: String?
    var events: [ObservabilityEventSnapshot]
    var isFrozen: Bool
    var recoveredAfterRestart: Bool
}

struct ObservabilityHealthIssue: Codable, Equatable, Identifiable {
    enum Source: String, Codable {
        case catalog
        case core
        case ingress
        case resourceIdentity
        case runtime
        case session
        case signpost
        case writer
    }

    let source: Source
    let code: String

    var id: String {
        "\(source.rawValue):\(code)"
    }
}

struct AppObservabilityHealth: Equatable {
    var initialized = false
    var mode: AppObservabilityMode = .disabled
    var memoryEventCount = 0
    var memoryCapacity = 0
    var oldestEventTimestampMilliseconds: Int64?
    var fileUsageBytes: Int64 = 0
    var diskBudgetBytes: Int64 = 0
    var droppedEvents: UInt64 = 0
    var droppedTraceEvents: UInt64 = 0
    var droppedDebugEvents: UInt64 = 0
    var droppedInfoEvents: UInt64 = 0
    var droppedWarnEvents: UInt64 = 0
    var droppedErrorEvents: UInt64 = 0
    var ingressDroppedEvents: UInt64 = 0
    var rejectedEvents: UInt64 = 0
    var coreRedactionRejectedEvents: UInt64 = 0
    var coreQueueDepth: UInt64 = 0
    var coreQueueCapacity: UInt64 = 0
    var writerAvailable = false
    var coreCallbackConnected = false
    var lastRotationAtMilliseconds: Int64?
    var incidentCount = 0
    var activeIncidentID: String?
    var degradedReason: String?
    var issues: [ObservabilityHealthIssue] = []
}

struct ObservabilityEventRing {
    private var storage: [ObservabilityEventSnapshot] = []
    private var startIndex = 0

    var count: Int {
        storage.count
    }

    var first: ObservabilityEventSnapshot? {
        guard !storage.isEmpty else { return nil }
        return storage[startIndex]
    }

    mutating func append(_ event: ObservabilityEventSnapshot, capacity: Int) {
        guard capacity > 0 else {
            removeAll()
            return
        }
        if storage.count < capacity {
            storage.append(event)
        } else {
            storage[startIndex] = event
            startIndex = (startIndex + 1) % capacity
        }
    }

    mutating func setCapacity(_ capacity: Int) {
        storage = suffix(capacity)
        startIndex = 0
    }

    mutating func removeAll() {
        storage.removeAll(keepingCapacity: true)
        startIndex = 0
    }

    func suffix(_ limit: Int) -> [ObservabilityEventSnapshot] {
        Array(elements().suffix(max(0, min(limit, storage.count))))
    }

    func elements() -> [ObservabilityEventSnapshot] {
        guard startIndex > 0 else { return storage }
        return Array(storage[startIndex...]) + Array(storage[..<startIndex])
    }
}

struct ObservabilityIncidentRecord: Codable {
    enum Kind: String, Codable {
        case header
        case event
        case freeze
        case status
    }

    var kind: Kind
    var incidentID: String
    var incident: ObservabilityIncidentSnapshot?
    var event: ObservabilityEventSnapshot?
    var status: ObservabilityIncidentStatus?
    var frozenAtMilliseconds: Int64?

    static func header(_ incident: ObservabilityIncidentSnapshot) -> Self {
        var header = incident
        header.events = []
        return Self(kind: .header, incidentID: incident.id, incident: header)
    }

    static func event(_ incidentID: String, _ event: ObservabilityEventSnapshot) -> Self {
        Self(kind: .event, incidentID: incidentID, event: event)
    }

    static func freeze(_ incidentID: String, _ timestamp: Int64) -> Self {
        Self(kind: .freeze, incidentID: incidentID, frozenAtMilliseconds: timestamp)
    }

    static func status(
        _ incidentID: String,
        _ status: ObservabilityIncidentStatus,
        _ frozenAtMilliseconds: Int64?
    ) -> Self {
        Self(
            kind: .status,
            incidentID: incidentID,
            status: status,
            frozenAtMilliseconds: frozenAtMilliseconds
        )
    }
}

struct ObservabilityOwnedFile {
    var url: URL
    var size: Int64
    var modifiedAt: Date
}

enum ObservabilityStoreError: Error, Equatable {
    case applicationSupportUnavailable
    case budgetExceeded
    case corruptManifest
    case createFailed
    case durabilityUncertain
    case eventTooLarge
    case fileTooLarge
    case incidentTooLarge
    case invalidIdentifier
    case openFailed
    case permissionsFailed
    case readOnly
    case unsupportedSchema
    case unavailable
    case unsafePath
}

extension ObservabilityIncidentSnapshot {
    static func recovered(
        from records: [ObservabilityIncidentRecord],
        currentSessionID: String,
        nowMilliseconds: Int64,
        maximumEvents: Int
    ) -> Self? {
        var snapshot: Self?
        var recoveredEvents = ObservabilityEventRing()
        var sawFreeze = false
        for record in records {
            switch record.kind {
            case .header:
                snapshot = record.incident
            case .event:
                guard snapshot?.id == record.incidentID, let event = record.event else { continue }
                recoveredEvents.append(event, capacity: maximumEvents)
            case .freeze:
                guard var current = snapshot,
                      current.id == record.incidentID,
                      let frozenAtMilliseconds = record.frozenAtMilliseconds
                else { continue }
                sawFreeze = true
                current.captureEndsAtMilliseconds = min(
                    current.captureEndsAtMilliseconds,
                    frozenAtMilliseconds
                )
                snapshot = current
            case .status:
                guard var current = snapshot,
                      current.id == record.incidentID,
                      let status = record.status
                else { continue }
                current.status = status
                if let frozenAtMilliseconds = record.frozenAtMilliseconds {
                    sawFreeze = true
                    current.captureEndsAtMilliseconds = min(
                        current.captureEndsAtMilliseconds,
                        frozenAtMilliseconds
                    )
                }
                snapshot = current
            }
        }
        guard var snapshot else { return nil }
        snapshot.events = recoveredEvents.elements()
        let restarted = snapshot.sessionID != currentSessionID
        snapshot.recoveredAfterRestart = restarted
        snapshot.isFrozen = snapshot.isFrozen || sawFreeze || restarted
            || snapshot.captureEndsAtMilliseconds <= nowMilliseconds
        return snapshot
    }
}
