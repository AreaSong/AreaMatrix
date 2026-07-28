import Foundation

struct CoreImportTraceContext: Equatable {
    var traceID: String
    var spanID: String
    var operationID: String
    var retryOfOperationID: String?
    var actionID: String
    var componentID: String

    static func singleFile() -> Self {
        operation(
            actionID: "repository.import.single.confirmed",
            componentID: "macos.import.single"
        )
    }

    static func operation(
        traceID: String = UUID().uuidString.lowercased(),
        retryOfOperationID: String? = nil,
        actionID: String,
        componentID: String
    ) -> Self {
        Self(
            traceID: traceID,
            spanID: UUID().uuidString.lowercased(),
            operationID: UUID().uuidString.lowercased(),
            retryOfOperationID: retryOfOperationID,
            actionID: actionID,
            componentID: componentID
        )
    }
}

struct CoreObservedImportRequest {
    var repoPath: String
    var sourceURL: URL
    var overrideCategory: String
    var overrideFilename: String
    var duplicateStrategy: DuplicateStrategy
    var traceContext: CoreImportTraceContext
}

protocol CoreObservedFileImporting: CoreFileImporting {
    func importCopiedFile(request: CoreObservedImportRequest) async throws -> FileEntrySnapshot
    func importMovedFile(request: CoreObservedImportRequest) async throws -> FileEntrySnapshot
    func importIndexedFile(request: CoreObservedImportRequest) async throws -> FileEntrySnapshot
}

func recordImportTerminal(
    _ appContext: CoreImportTraceContext,
    coreTraceContext: CoreTraceContext,
    outcome: String,
    error: Error? = nil
) async {
    var event = ObservabilitySemanticEventInput(
        actionID: appContext.actionID,
        componentID: appContext.componentID
    )
    event.traceID = appContext.traceID
    event.spanID = appContext.spanID
    event.operationID = appContext.operationID
    event.retryOfOperationID = appContext.retryOfOperationID
    event.phase = "completed"
    event.outcome = outcome
    event.severity = outcome == "failed" ? .error : (outcome == "degraded" ? .warn : .info)
    event.resources = coreTraceContext.resourceRefs.map(ObservabilityResourceSnapshot.init)
    event.attributes = coreTraceContext.attributes.map(ObservabilityAttributeSnapshot.init)
    event.error = error.map(observabilityErrorSnapshot)
    await AppLogger.shared.record(event)
}

private func observabilityErrorSnapshot(_ error: Error) -> ObservabilityErrorSnapshot {
    guard let context = CoreErrorRawContextSnapshot(error) else {
        return ObservabilityErrorSnapshot(code: "app.unexpected", kind: "unexpected", technicalDetails: nil)
    }
    return ObservabilityErrorSnapshot(
        code: "core.\(context.kind.rawValue.lowercased())",
        kind: context.kind.rawValue,
        technicalDetails: nil
    )
}
