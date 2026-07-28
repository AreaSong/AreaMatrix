import Foundation

enum ObservabilityHubEventFactory {
    private static let incidentPreWindowMilliseconds: Int64 = 5 * 60 * 1000
    private static let incidentPostWindowMilliseconds: Int64 = 30 * 1000

    struct SemanticContext {
        let eventID: String
        let timestamp: Int64
        let monotonicTimestamp: UInt64
        let sequenceNumber: UInt64
        let sessionID: String
        let incidentID: String?
    }

    struct IncidentContext {
        let id: String
        let sessionID: String
        let markedAt: Int64
        let note: String?
        let events: [ObservabilityEventSnapshot]
        let capacity: Int
    }

    struct RecoveryContext {
        let id: String
        let previousSessionID: String
        let nowMilliseconds: Int64
        let events: [ObservabilityEventSnapshot]
    }

    static func semanticEvent(
        _ input: ObservabilitySemanticEventInput,
        context: SemanticContext
    ) -> ObservabilityEventSnapshot {
        ObservabilityEventSnapshot(
            schemaVersion: 2,
            eventID: context.eventID,
            wallTimestampMilliseconds: context.timestamp,
            monotonicTimestampNanoseconds: context.monotonicTimestamp,
            sequenceNumber: context.sequenceNumber,
            sessionID: context.sessionID,
            incidentID: context.incidentID,
            traceID: input.traceID,
            spanID: input.spanID,
            parentSpanID: input.parentSpanID,
            operationID: input.operationID,
            retryOfOperationID: input.retryOfOperationID,
            actionID: input.actionID,
            componentID: input.componentID,
            layer: input.layer,
            phase: input.phase,
            severity: input.severity,
            outcome: input.outcome,
            durationMilliseconds: input.durationMilliseconds,
            resources: input.resources,
            error: input.error,
            attributes: input.attributes,
            privacy: input.resolvedPrivacy,
            message: input.message,
            target: input.target,
            threadName: Thread.current.name,
            buildContext: .currentApp
        )
    }

    static func incident(_ context: IncidentContext) -> ObservabilityIncidentSnapshot {
        let lowerBound = context.markedAt - Self.incidentPreWindowMilliseconds
        let captured = context.events.filter {
            $0.wallTimestampMilliseconds >= lowerBound && $0.wallTimestampMilliseconds <= context.markedAt
        }.map { ObservabilityHubPolicy.tagged($0, incidentID: context.id) }
        return ObservabilityIncidentSnapshot(
            id: context.id,
            sessionID: context.sessionID,
            markedAtMilliseconds: context.markedAt,
            captureEndsAtMilliseconds: context.markedAt + Self.incidentPostWindowMilliseconds,
            status: .open,
            note: ObservabilityHubPolicy.sanitizedNote(context.note),
            events: Array(captured.suffix(context.capacity)),
            isFrozen: false,
            recoveredAfterRestart: false
        )
    }

    static func recoveredIncident(_ context: RecoveryContext) -> ObservabilityIncidentSnapshot {
        let markedAt = context.events.last?.wallTimestampMilliseconds ?? context.nowMilliseconds
        return ObservabilityIncidentSnapshot(
            id: context.id,
            sessionID: context.previousSessionID,
            markedAtMilliseconds: markedAt,
            captureEndsAtMilliseconds: markedAt,
            status: .open,
            note: nil,
            events: context.events.map { ObservabilityHubPolicy.tagged($0, incidentID: context.id) },
            isFrozen: true,
            recoveredAfterRestart: true
        )
    }

    static func sanitized(
        _ event: ObservabilityEventSnapshot,
        includeSensitive: Bool,
        catalog: ObservabilityCatalog?,
        buildScope: ObservabilitySafetyPolicy.BuildScope
    ) -> ObservabilityEventSnapshot? {
        guard let catalog else { return nil }
        return ObservabilityHubPolicy.sanitize(
            event,
            includeSensitive: includeSensitive,
            catalog: catalog,
            buildScope: buildScope
        )
    }
}

extension ObservabilityHub {
    static let shared = ObservabilityHub()

    enum IncidentError: Error, Equatable {
        case invalidStatus
        case notFound
        case persistenceUnavailable
        case readOnly
        case runtimeStopped
    }
}
