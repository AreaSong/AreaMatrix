import Foundation

struct ObservabilityTraceContextRequest {
    let traceID: String
    let parentSpanID: String?
    let operationID: String
    let actionID: String
    let componentID: String
    let incidentID: String?
    let retryOfOperationID: String?
    let sourceURL: URL?
    let storageMode: StorageMode?
}

protocol CoreImportTraceContextProviding: Sendable {
    func make(_ request: ObservabilityTraceContextRequest) async -> CoreTraceContext
}

struct ObservabilityTraceContextFactory: CoreImportTraceContextProviding {
    let hub: ObservabilityHub
    let resourceIdentityProvider: ObservabilityResourceIdentityProvider
    let sessionID: String

    func make(_ request: ObservabilityTraceContextRequest) async -> CoreTraceContext {
        let resolvedIncidentID = await resolvedIncidentID(explicit: request.incidentID)
        let resourceRefs = await resourceReferences(
            sourceURL: request.sourceURL,
            storageMode: request.storageMode
        )
        let attributes = request.sourceURL.map {
            [CoreObservabilityAttribute(
                key: "source.name",
                value: $0.lastPathComponent,
                privacy: .sensitive
            )]
        } ?? []
        return CoreTraceContext(
            sessionId: sessionID,
            traceId: request.traceID,
            parentSpanId: request.parentSpanID,
            incidentId: resolvedIncidentID,
            operationId: request.operationID,
            retryOfOperationId: request.retryOfOperationID,
            actionId: request.actionID,
            componentId: request.componentID,
            resourceRefs: resourceRefs,
            attributes: attributes
        )
    }

    private func resolvedIncidentID(explicit incidentID: String?) async -> String? {
        if let incidentID { return incidentID }
        return await hub.activeIncidentID()
    }

    private func resourceReferences(
        sourceURL: URL?,
        storageMode: StorageMode?
    ) async -> [CoreObservabilityResourceRef] {
        guard let sourceURL, let storageMode else { return [] }
        let identity = await resourceIdentityProvider.identity(for: sourceURL, storageMode: storageMode)
        if let reason = identity.degradedReason {
            await hub.noteResourceIdentityDegraded(reason: reason)
        }
        return identity.reference.map { [$0] } ?? []
    }
}
