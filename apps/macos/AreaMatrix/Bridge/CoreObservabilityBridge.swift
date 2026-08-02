import Foundation

enum CoreObservabilityModeSnapshot: Equatable {
    case disabled
    case standard
    case diagnostic
    case developer
}

enum CoreObservabilitySeveritySnapshot: Equatable {
    case trace
    case debug
    case info
    case warn
    case error
}

struct CoreObservabilityConfigurationSnapshot: Equatable {
    var sessionID: String
    var mode: CoreObservabilityModeSnapshot
    var minimumSeverity: CoreObservabilitySeveritySnapshot
    var queueCapacity: UInt64
    var includeSensitive: Bool
}

struct CoreObservabilityHealthSnapshot: Equatable {
    var initialized: Bool
    var mode: CoreObservabilityModeSnapshot
    var queueDepth: UInt64
    var queueCapacity: UInt64
    var droppedTrace: UInt64
    var droppedDebug: UInt64
    var droppedInfo: UInt64
    var droppedWarn: UInt64
    var droppedError: UInt64
    var redactionRejected: UInt64
    var callbackConnected: Bool
    var degraded: Bool
    var degradedReason: String?
}

protocol CoreObservabilityEventSinking: AnyObject, Sendable {
    func onEvent(_ event: ObservabilityEventSnapshot)
}

protocol CoreObservabilityControlling: Sendable {
    func observabilityBuildContext() async -> ObservabilityBuildContextSnapshot
    func initializeObservability(
        config: CoreObservabilityConfigurationSnapshot,
        sink: any CoreObservabilityEventSinking
    ) async throws -> CoreObservabilityHealthSnapshot
    func updateObservability(
        config: CoreObservabilityConfigurationSnapshot
    ) async throws -> CoreObservabilityHealthSnapshot
    func observabilityHealth() async -> CoreObservabilityHealthSnapshot
    func flushObservability(deadlineMilliseconds: UInt64) async throws -> CoreObservabilityHealthSnapshot
}

extension CoreBridge: CoreObservabilityControlling {
    func observabilityBuildContext() async -> ObservabilityBuildContextSnapshot {
        ObservabilityBuildContextSnapshot(getCoreObservabilityBuildContext())
    }

    func initializeObservability(
        config: CoreObservabilityConfigurationSnapshot,
        sink: any CoreObservabilityEventSinking
    ) async throws -> CoreObservabilityHealthSnapshot {
        try CoreObservabilityHealthSnapshot(initializeCoreObservability(
            config: ObservabilityConfig(config),
            sink: CoreObservabilitySinkBridgeAdapter(sink: sink)
        ))
    }

    func updateObservability(
        config: CoreObservabilityConfigurationSnapshot
    ) async throws -> CoreObservabilityHealthSnapshot {
        try CoreObservabilityHealthSnapshot(updateCoreObservability(config: ObservabilityConfig(config)))
    }

    func observabilityHealth() async -> CoreObservabilityHealthSnapshot {
        CoreObservabilityHealthSnapshot(getCoreObservabilityHealth())
    }

    func flushObservability(deadlineMilliseconds: UInt64) async throws -> CoreObservabilityHealthSnapshot {
        try CoreObservabilityHealthSnapshot(flushCoreObservability(
            deadlineMilliseconds: deadlineMilliseconds
        ))
    }
}

private final class CoreObservabilitySinkBridgeAdapter: CoreObservabilitySink, @unchecked Sendable {
    private let sink: any CoreObservabilityEventSinking

    init(sink: any CoreObservabilityEventSinking) {
        self.sink = sink
    }

    func onEvent(event: CoreObservabilityEvent) {
        sink.onEvent(ObservabilityEventSnapshot(coreEvent: event))
    }
}

private func getCoreObservabilityBuildContext() -> ObservabilityBuildContext {
    getObservabilityBuildContext()
}

private func initializeCoreObservability(
    config: ObservabilityConfig,
    sink: any CoreObservabilitySink
) throws -> ObservabilityHealth {
    try initializeObservability(config: config, sink: sink)
}

private func updateCoreObservability(config: ObservabilityConfig) throws -> ObservabilityHealth {
    try updateObservabilityConfig(config: config)
}

private func getCoreObservabilityHealth() -> ObservabilityHealth {
    getObservabilityHealth()
}

private func flushCoreObservability(deadlineMilliseconds: UInt64) throws -> ObservabilityHealth {
    try flushObservability(deadlineMs: deadlineMilliseconds)
}

private extension ObservabilityConfig {
    init(_ snapshot: CoreObservabilityConfigurationSnapshot) {
        self.init(
            sessionId: snapshot.sessionID,
            mode: snapshot.mode.coreValue,
            minimumSeverity: snapshot.minimumSeverity.coreValue,
            queueCapacity: snapshot.queueCapacity,
            includeSensitive: snapshot.includeSensitive
        )
    }
}

private extension CoreObservabilityHealthSnapshot {
    init(_ health: ObservabilityHealth) {
        self.init(
            initialized: health.initialized,
            mode: CoreObservabilityModeSnapshot(health.mode),
            queueDepth: health.queueDepth,
            queueCapacity: health.queueCapacity,
            droppedTrace: health.droppedTrace,
            droppedDebug: health.droppedDebug,
            droppedInfo: health.droppedInfo,
            droppedWarn: health.droppedWarn,
            droppedError: health.droppedError,
            redactionRejected: health.redactionRejected,
            callbackConnected: health.callbackConnected,
            degraded: health.degraded,
            degradedReason: health.degradedReason
        )
    }
}

private extension CoreObservabilityModeSnapshot {
    init(_ mode: ObservabilityMode) {
        switch mode {
        case .disabled: self = .disabled
        case .standard: self = .standard
        case .diagnostic: self = .diagnostic
        case .developer: self = .developer
        }
    }

    var coreValue: ObservabilityMode {
        switch self {
        case .disabled: .disabled
        case .standard: .standard
        case .diagnostic: .diagnostic
        case .developer: .developer
        }
    }
}

private extension CoreObservabilitySeveritySnapshot {
    var coreValue: ObservabilitySeverity {
        switch self {
        case .trace: .trace
        case .debug: .debug
        case .info: .info
        case .warn: .warn
        case .error: .error
        }
    }
}

extension ObservabilityEventSnapshot {
    init(coreEvent: CoreObservabilityEvent) {
        self.init(
            schemaVersion: coreEvent.schemaVersion,
            eventID: coreEvent.eventId,
            wallTimestampMilliseconds: coreEvent.wallTimestampMs,
            monotonicTimestampNanoseconds: coreEvent.monotonicTimestampNs,
            sequenceNumber: coreEvent.sequenceNumber,
            sessionID: coreEvent.sessionId,
            incidentID: coreEvent.incidentId,
            traceID: coreEvent.traceId,
            spanID: coreEvent.spanId,
            parentSpanID: coreEvent.parentSpanId,
            operationID: coreEvent.operationId,
            retryOfOperationID: coreEvent.retryOfOperationId,
            actionID: coreEvent.actionId,
            componentID: coreEvent.componentId,
            layer: coreEvent.layer.snapshotValue,
            phase: coreEvent.phase,
            severity: coreEvent.severity.snapshotValue,
            outcome: coreEvent.outcome.snapshotValue,
            durationMilliseconds: coreEvent.durationMs,
            resources: coreEvent.resourceRefs.map(ObservabilityResourceSnapshot.init),
            error: coreEvent.error.map(ObservabilityErrorSnapshot.init),
            attributes: coreEvent.attributes.map(ObservabilityAttributeSnapshot.init),
            privacy: coreEvent.privacyLevel.snapshotValue,
            message: coreEvent.message,
            target: coreEvent.target,
            threadName: coreEvent.threadName,
            buildContext: ObservabilityBuildContextSnapshot(coreEvent.buildContext)
        )
    }
}

extension ObservabilityBuildContextSnapshot {
    init(_ context: ObservabilityBuildContext) {
        self.init(
            producer: context.producer,
            version: context.version,
            build: context.build,
            configuration: context.configuration,
            platform: context.platform,
            architecture: context.architecture
        )
    }
}

extension ObservabilityResourceSnapshot {
    init(_ resource: CoreObservabilityResourceRef) {
        self.init(
            resourceID: resource.resourceId,
            alias: resource.alias,
            pathExtension: resource.extension,
            sizeBucket: resource.sizeBucket,
            storageMode: resource.storageMode
        )
    }
}

private extension ObservabilityErrorSnapshot {
    init(_ error: CoreObservabilityError) {
        self.init(code: error.code, kind: error.kind, technicalDetails: error.technicalDetails)
    }
}

extension ObservabilityAttributeSnapshot {
    init(_ attribute: CoreObservabilityAttribute) {
        self.init(
            key: attribute.key,
            value: attribute.value,
            privacy: attribute.privacy.snapshotValue
        )
    }
}

private extension ObservabilityLayer {
    var snapshotValue: String {
        switch self {
        case .swiftUi: "swift_ui"
        case .platform: "platform"
        case .bridge: "bridge"
        case .core: "core"
        case .database: "database"
        case .filesystem: "filesystem"
        case .network: "network"
        }
    }
}

private extension ObservabilitySeverity {
    var snapshotValue: AppObservabilitySeverity {
        switch self {
        case .trace: .trace
        case .debug: .debug
        case .info: .info
        case .warn: .warn
        case .error: .error
        }
    }
}

private extension ObservabilityOutcome {
    var snapshotValue: String {
        switch self {
        case .none: "none"
        case .started: "started"
        case .succeeded: "succeeded"
        case .failed: "failed"
        case .cancelled: "cancelled"
        case .skipped: "skipped"
        case .degraded: "degraded"
        }
    }
}

private extension ObservabilityPrivacy {
    var snapshotValue: String {
        switch self {
        case .public: "public"
        case .pseudonymous: "pseudonymous"
        case .sensitive: "sensitive"
        case .prohibited: "prohibited"
        }
    }
}
