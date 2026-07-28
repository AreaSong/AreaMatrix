import Foundation

protocol CoreObservabilityControlling: Sendable {
    func observabilityBuildContext() async -> ObservabilityBuildContextSnapshot
    func initializeObservability(
        config: ObservabilityConfig,
        sink: any CoreObservabilitySink
    ) async throws -> ObservabilityHealth
    func updateObservability(config: ObservabilityConfig) async throws -> ObservabilityHealth
    func observabilityHealth() async -> ObservabilityHealth
    func flushObservability(deadlineMilliseconds: UInt64) async throws -> ObservabilityHealth
}

extension CoreBridge: CoreObservabilityControlling {
    func observabilityBuildContext() async -> ObservabilityBuildContextSnapshot {
        ObservabilityBuildContextSnapshot(getCoreObservabilityBuildContext())
    }

    func initializeObservability(
        config: ObservabilityConfig,
        sink: any CoreObservabilitySink
    ) async throws -> ObservabilityHealth {
        try initializeCoreObservability(config: config, sink: sink)
    }

    func updateObservability(config: ObservabilityConfig) async throws -> ObservabilityHealth {
        try updateCoreObservability(config: config)
    }

    func observabilityHealth() async -> ObservabilityHealth {
        getCoreObservabilityHealth()
    }

    func flushObservability(deadlineMilliseconds: UInt64) async throws -> ObservabilityHealth {
        try flushCoreObservability(deadlineMilliseconds: deadlineMilliseconds)
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
