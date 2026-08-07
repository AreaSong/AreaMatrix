import Combine
import Foundation

@MainActor
final class ObservabilityRuntimeAssembly: ObservableObject {
    @Published private(set) var state: State = .idle
    @Published private(set) var recoveryNotice: ObservabilityRecoveryNotice?

    let hub: ObservabilityHub
    private let core: any CoreObservabilityControlling
    private let sink: CoreObservabilitySinkAdapter
    private let traceContextFactory: ObservabilityTraceContextFactory
    private let configuredSessionStore: ObservabilitySessionLifecycleStore?
    let sessionID: String
    private let scheduler: ObservabilityRuntimeScheduler
    private var resolvedSessionStore: ObservabilitySessionLifecycleStore?
    private var startupTask: Task<Void, Never>?
    private var mutationTail: Task<Void, Never>?
    private var leaseTask: Task<Void, Never>?
    private var stopTask: Task<ObservabilityStopReport, Never>?
    private var lastStopReport: ObservabilityStopReport?
    private var runtimeIssues: [ObservabilityHealthIssue] = []
    private var sessionStartedAtMilliseconds: Int64 = 0
    private var sessionMarkerStarted = false
    private var stopProgress = ObservabilityStopReport()
    private var currentStopStage: ObservabilityStopReport.Stage?

    init(
        hub: ObservabilityHub,
        core: any CoreObservabilityControlling,
        resourceIdentityProvider: ObservabilityResourceIdentityProvider,
        sessionStore: ObservabilitySessionLifecycleStore? = nil,
        sessionID: String = ObservabilityProcessIdentity.sessionID,
        scheduler: ObservabilityRuntimeScheduler
    ) {
        self.hub = hub
        self.core = core
        traceContextFactory = ObservabilityTraceContextFactory(
            hub: hub,
            resourceIdentityProvider: resourceIdentityProvider,
            sessionID: sessionID
        )
        configuredSessionStore = sessionStore
        self.sessionID = sessionID
        self.scheduler = scheduler
        sink = CoreObservabilitySinkAdapter(hub: hub)
    }

    func start() {
        guard state == .idle else { return }
        state = .starting
        startupTask = Task { [weak self] in
            guard let self else { return }
            let configuration = await performStartup()
            finishStartup(configuration: configuration)
        }
    }

    func update(_ configuration: AppObservabilityConfiguration) async throws {
        await ensureStarted()
        guard state == .running else { throw ObservabilityRuntimeError.notRunning }
        let normalized = ObservabilityRuntimePolicy.normalizedLease(configuration)
        try await enqueueMutation { [core, hub, sessionID] in
            _ = try await core.updateObservability(config: ObservabilityRuntimePolicy.coreConfiguration(
                normalized,
                sessionID: sessionID
            ))
            await hub.configure(normalized)
        }
        scheduleLease(for: normalized)
    }

    func health() async -> AppObservabilityHealth {
        if state == .starting { await startupTask?.value }
        let coreHealth: CoreObservabilityHealthSnapshot? = if state == .idle {
            nil
        } else {
            await core.observabilityHealth()
        }
        var health = await hub.health(core: coreHealth)
        for issue in runtimeIssues where !health.issues.contains(issue) {
            health.issues.append(issue)
        }
        health.degradedReason = health.issues.first?.code
        return health
    }

    func configurationSnapshot() async -> AppObservabilityConfiguration {
        await ensureStarted()
        return await hub.configurationSnapshot()
    }

    func removeLocalLogs() async throws {
        await ensureStarted()
        guard state == .running else { throw ObservabilityRuntimeError.notRunning }
        try await enqueueMutation { [hub] in
            try await hub.removeLocalLogs()
        }
    }

    func deleteIncident(id: String) async throws {
        await ensureStarted()
        guard state == .running else { throw ObservabilityRuntimeError.notRunning }
        try await enqueueMutation { [hub] in
            try await hub.deleteIncident(id: id)
        }
    }

    func stop(deadline: Duration = .seconds(5)) async -> ObservabilityStopReport {
        if let stopTask { return await stopTask.value }
        if state == .stopped { return lastStopReport ?? ObservabilityStopReport() }

        state = .stopping
        leaseTask?.cancel()
        leaseTask = nil
        let timeoutMilliseconds = max(1, deadline.clampedMilliseconds)
        let task = Task { [weak self] in
            guard let self else {
                return ObservabilityStopReport(
                    failures: [.init(stage: .storeClose, code: "runtime-released")]
                )
            }
            return await runStopWithDeadline(timeoutMilliseconds: timeoutMilliseconds)
        }
        stopTask = task
        let report = await task.value
        sink.closeIngress()
        await hub.stopAcceptingEvents()
        lastStopReport = report
        state = .stopped
        if !report.succeeded {
            appendRuntimeIssue(source: .runtime, code: report.timedOut ? "stop-timeout" : "stop-degraded")
        }
        return report
    }

    func dismissRecoveryNotice() {
        recoveryNotice = nil
    }

    func makeCoreTraceContext(
        traceID: String = UUID().uuidString.lowercased(),
        parentSpanID: String? = nil,
        operationID: String = UUID().uuidString.lowercased(),
        actionID: String,
        componentID: String,
        incidentID: String? = nil,
        retryOfOperationID: String? = nil,
        sourceURL: URL? = nil,
        storageMode: StorageMode? = nil
    ) async -> CoreTraceContext {
        await makeCoreTraceContext(.init(
            traceID: traceID,
            parentSpanID: parentSpanID,
            operationID: operationID,
            actionID: actionID,
            componentID: componentID,
            incidentID: incidentID,
            retryOfOperationID: retryOfOperationID,
            sourceURL: sourceURL,
            storageMode: storageMode
        ))
    }

    func makeCoreTraceContext(_ request: ObservabilityTraceContextRequest) async -> CoreTraceContext {
        await ensureStarted()
        return await traceContextFactory.make(request)
    }
}

private extension ObservabilityRuntimeAssembly {
    func ensureStarted() async {
        if state == .idle { start() }
        await startupTask?.value
    }

    func performStartup() async -> AppObservabilityConfiguration {
        let stored = await hub.configurationSnapshot()
        let configuration = ObservabilityConfigurationResolver.resolveForLaunch(
            stored,
            nowMilliseconds: scheduler.nowMilliseconds(),
            sessionID: sessionID
        )
        await hub.configure(configuration)
        await beginSessionLifecycle()
        let coreBuildContext = await core.observabilityBuildContext()
        guard await hub.configureCoreBuildContext(coreBuildContext) else {
            await recordCoreStartupFailure(code: "core-build-context-invalid")
            return configuration
        }
        do {
            _ = try await core.initializeObservability(
                config: ObservabilityRuntimePolicy.coreConfiguration(configuration, sessionID: sessionID),
                sink: sink
            )
        } catch {
            await recordCoreStartupFailure(code: "core-initialization-failed")
        }
        return configuration
    }

    func recordCoreStartupFailure(code: String) async {
        appendRuntimeIssue(source: .runtime, code: code)
        var event = ObservabilitySemanticEventInput(
            actionID: "observability.runtime.initialization",
            componentID: "macos.observability.runtime"
        )
        event.phase = "initialization"
        event.severity = .error
        event.outcome = "degraded"
        await hub.recordSemanticAction(event)
    }

    func finishStartup(configuration: AppObservabilityConfiguration) {
        guard state == .starting else { return }
        state = .running
        scheduleLease(for: configuration)
    }

    func beginSessionLifecycle() async {
        let rootURL = await hub.storageRootURLSnapshot()
        let store = configuredSessionStore ?? ObservabilitySessionLifecycleStore(rootURL: rootURL)
        resolvedSessionStore = store
        sessionStartedAtMilliseconds = scheduler.nowMilliseconds()
        let startedAtMilliseconds = sessionStartedAtMilliseconds
        let currentSessionID = sessionID
        do {
            let previous = try await Task.detached {
                try store.beginSession(
                    sessionID: currentSessionID,
                    nowMilliseconds: startedAtMilliseconds
                )
            }.value
            sessionMarkerStarted = configuredSessionStore != nil || rootURL != nil
            switch previous {
            case .missing, .clean:
                break
            case let .interrupted(marker):
                if let incidentID = await hub.recoverInterruptedSession(
                    previousSessionID: marker.sessionID,
                    nowMilliseconds: scheduler.nowMilliseconds()
                ) {
                    recoveryNotice = ObservabilityRecoveryNotice(incidentID: incidentID)
                } else {
                    appendRuntimeIssue(source: .session, code: "interrupted-session-recovery-failed")
                }
            case .corrupt:
                appendRuntimeIssue(source: .session, code: "session-marker-corrupt")
            }
        } catch {
            appendRuntimeIssue(source: .session, code: "session-marker-unavailable")
        }
    }

    func enqueueMutation(
        _ operation: @escaping @Sendable () async throws -> Void
    ) async throws {
        let predecessor = mutationTail
        let operationTask = Task<Void, Error> {
            await predecessor?.value
            try await operation()
        }
        mutationTail = Task { _ = await operationTask.result }
        try await operationTask.value
    }

    func scheduleLease(for configuration: AppObservabilityConfiguration) {
        leaseTask?.cancel()
        leaseTask = nil
        guard state == .running,
              configuration.mode.supportsExpiry,
              let lease = configuration.modeLease,
              lease.policy == .timed,
              let expiry = lease.expiresAtMilliseconds
        else { return }
        let expectedLease = lease
        let scheduler = scheduler
        leaseTask = Task { [weak self] in
            let delay = ObservabilityRuntimePolicy.delayMilliseconds(
                until: expiry,
                now: scheduler.nowMilliseconds()
            )
            try? await scheduler.sleep(.milliseconds(delay))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            let current = await hub.configurationSnapshot()
            guard current.modeLease == expectedLease else { return }
            do {
                try await update(.standard)
            } catch {
                appendRuntimeIssue(source: .runtime, code: "mode-lease-revert-failed")
            }
        }
    }

    func runStopWithDeadline(timeoutMilliseconds: Int64) async -> ObservabilityStopReport {
        stopProgress = ObservabilityStopReport()
        currentStopStage = .acceptedMutations
        let deadlineNanoseconds = ObservabilityRuntimePolicy.saturatingAdd(
            scheduler.nowUptimeNanoseconds(),
            ObservabilityRuntimePolicy.saturatingMultiply(UInt64(timeoutMilliseconds), 1_000_000)
        )
        let operation = Task { [weak self] in
            guard let self else { return ObservabilityStopReport() }
            return await performStop(deadlineNanoseconds: deadlineNanoseconds)
        }
        return await raceStop(operation, timeoutMilliseconds: timeoutMilliseconds)
    }

    func performStop(deadlineNanoseconds: UInt64) async -> ObservabilityStopReport {
        await startupTask?.value
        await mutationTail?.value
        guard recordCompleted(.acceptedMutations, before: deadlineNanoseconds) else { return stopProgress }
        currentStopStage = nil

        let configuration = await hub.configurationSnapshot()
        var disabledConfiguration = configuration
        disabledConfiguration.mode = .disabled
        disabledConfiguration.modeLease = nil
        await runStopStage(.coreProducerGate, before: deadlineNanoseconds) {
            _ = try await core.updateObservability(config: ObservabilityRuntimePolicy.coreConfiguration(
                disabledConfiguration,
                sessionID: sessionID
            ))
        }
        await runStopStage(.coreFlush, before: deadlineNanoseconds) {
            _ = try await core.flushObservability(
                deadlineMilliseconds: remainingMilliseconds(before: deadlineNanoseconds)
            )
        }
        await runStopStage(.adapterDrain, before: deadlineNanoseconds) {
            await sink.finishAndDrain()
        }
        await runStopStage(.hubFlush, before: deadlineNanoseconds) {
            try await hub.flush()
        }
        await runStopStage(.storeClose, before: deadlineNanoseconds) {
            try await hub.shutdown()
        }

        guard stopProgress.failures.isEmpty,
              !stopProgress.timedOut,
              sessionMarkerStarted,
              let store = resolvedSessionStore
        else { return stopProgress }
        let currentSessionID = sessionID
        let startedAtMilliseconds = sessionStartedAtMilliseconds
        let closedAtMilliseconds = scheduler.nowMilliseconds()
        await runStopStage(.sessionMarker, before: deadlineNanoseconds) {
            try await Task.detached {
                try store.closeSession(
                    sessionID: currentSessionID,
                    startedAtMilliseconds: startedAtMilliseconds,
                    nowMilliseconds: closedAtMilliseconds
                )
            }.value
        }
        stopProgress.cleanSessionMarkerWritten = stopProgress.failures.isEmpty && !stopProgress.timedOut
        return stopProgress
    }

    func runStopStage(
        _ stage: ObservabilityStopReport.Stage,
        before deadline: UInt64,
        operation: () async throws -> Void
    ) async {
        guard !deadlineExpired(deadline) else {
            recordTimeout(stage)
            return
        }
        currentStopStage = stage
        defer {
            if currentStopStage == stage { currentStopStage = nil }
        }
        do {
            try await operation()
            guard !deadlineExpired(deadline), !Task.isCancelled else {
                recordTimeout(stage)
                return
            }
            stopProgress.completedStages.append(stage)
        } catch {
            stopProgress.failures.append(.init(
                stage: stage,
                code: ObservabilityRuntimePolicy.stableErrorCode(error)
            ))
        }
    }

    func recordCompleted(_ stage: ObservabilityStopReport.Stage, before deadline: UInt64) -> Bool {
        guard !deadlineExpired(deadline), !Task.isCancelled else {
            recordTimeout(stage)
            return false
        }
        stopProgress.completedStages.append(stage)
        return true
    }

    func recordTimeout(_ stage: ObservabilityStopReport.Stage) {
        stopProgress.timedOut = true
        if !stopProgress.failures.contains(where: { $0.stage == stage }) {
            stopProgress.failures.append(.init(stage: stage, code: "deadline-exceeded"))
        }
    }

    func raceStop(
        _ operation: Task<ObservabilityStopReport, Never>,
        timeoutMilliseconds: Int64
    ) async -> ObservabilityStopReport {
        let gate = ObservabilityStopRaceGate()
        return await withCheckedContinuation { continuation in
            let timeoutTask = Task { [weak self] in
                guard let self else { return }
                try? await scheduler.sleep(.milliseconds(timeoutMilliseconds))
                guard !Task.isCancelled else { return }
                var report = stopProgress
                report.timedOut = true
                let timedOutStage = currentStopStage ?? .acceptedMutations
                if !report.failures.contains(where: { $0.stage == timedOutStage }) {
                    report.failures.append(.init(stage: timedOutStage, code: "deadline-exceeded"))
                }
                if gate.resolve(report, continuation: continuation) {
                    operation.cancel()
                }
            }
            Task {
                let report = await operation.value
                if gate.resolve(report, continuation: continuation) {
                    timeoutTask.cancel()
                }
            }
        }
    }

    func remainingMilliseconds(before deadline: UInt64) -> UInt64 {
        let now = scheduler.nowUptimeNanoseconds()
        guard now < deadline else { return 1 }
        return max(1, (deadline - now) / 1_000_000)
    }

    func deadlineExpired(_ deadline: UInt64) -> Bool {
        scheduler.nowUptimeNanoseconds() >= deadline
    }

    func appendRuntimeIssue(source: ObservabilityHealthIssue.Source, code: String) {
        let issue = ObservabilityHealthIssue(source: source, code: code)
        if !runtimeIssues.contains(issue) { runtimeIssues.append(issue) }
    }
}
