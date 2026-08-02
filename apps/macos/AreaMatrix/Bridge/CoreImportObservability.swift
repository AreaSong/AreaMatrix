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
    var duplicateStrategy: ImportDuplicateStrategySnapshot
    var traceContext: CoreImportTraceContext
}

protocol CoreObservedFileImporting: CoreFileImporting {
    func importCopiedFile(request: CoreObservedImportRequest) async throws -> FileEntrySnapshot
    func importMovedFile(request: CoreObservedImportRequest) async throws -> FileEntrySnapshot
    func importIndexedFile(request: CoreObservedImportRequest) async throws -> FileEntrySnapshot
}

struct CoreImportObservabilityRecorder {
    static let live = Self(
        traceContextProvider: SharedCoreImportTraceContextProvider(),
        logger: .shared,
        enabled: true
    )

    /// XCTest must not inherit production Keychain and observability side effects.
    /// The test runner sets this flag explicitly; normal app launches keep the live path.
    static var defaultForCurrentProcess: Self {
        isTestProcess ? .testNoop : .live
    }

    private static var isTestProcess: Bool {
        let environment = ProcessInfo.processInfo.environment
        // Scheme environment variables are not consistently inherited by the
        // XCTest host. The XCTest configuration marker is the reliable
        // boundary for preventing production Keychain side effects in tests.
        return environment["AREAMATRIX_TEST_MODE"] == "1"
            || environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
    }

    private static let testNoop = Self(
        traceContextProvider: TestCoreImportTraceContextProvider(),
        logger: .shared,
        enabled: false
    )

    let traceContextProvider: any CoreImportTraceContextProviding
    let logger: AppLogger
    let enabled: Bool

    init(
        traceContextProvider: any CoreImportTraceContextProviding,
        logger: AppLogger,
        enabled: Bool = true
    ) {
        self.traceContextProvider = traceContextProvider
        self.logger = logger
        self.enabled = enabled
    }

    func recordTerminal(
        _ appContext: CoreImportTraceContext,
        coreTraceContext: CoreTraceContext,
        outcome: String,
        error: Error? = nil
    ) async {
        guard enabled else { return }
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
        await logger.record(event)
    }
}

private struct SharedCoreImportTraceContextProvider: CoreImportTraceContextProviding {
    func make(_ request: ObservabilityTraceContextRequest) async -> CoreTraceContext {
        await ObservabilityRuntimeAssembly.shared.makeCoreTraceContext(request)
    }
}

private struct TestCoreImportTraceContextProvider: CoreImportTraceContextProviding {
    func make(_ request: ObservabilityTraceContextRequest) async -> CoreTraceContext {
        CoreTraceContext(
            sessionId: "00000000-0000-0000-0000-000000000001",
            traceId: request.traceID,
            parentSpanId: request.parentSpanID,
            incidentId: request.incidentID,
            operationId: request.operationID,
            retryOfOperationId: request.retryOfOperationID,
            actionId: request.actionID,
            componentId: request.componentID,
            resourceRefs: [],
            attributes: []
        )
    }
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
