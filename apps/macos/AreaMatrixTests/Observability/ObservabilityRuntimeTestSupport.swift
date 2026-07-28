@testable import AreaMatrix
import Foundation
import XCTest

final class TestObservabilityRuntimeScheduler: @unchecked Sendable {
    private struct Sleeper {
        let id: UUID
        let duration: Duration
        let continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    private var wallMilliseconds: Int64
    private var uptimeNanoseconds: UInt64
    private var sleepers: [Sleeper] = []
    private var cancellationRequests = Set<UUID>()
    private var cancellationCount = 0

    init(wallMilliseconds: Int64 = 1000, uptimeNanoseconds: UInt64 = 1_000_000) {
        self.wallMilliseconds = wallMilliseconds
        self.uptimeNanoseconds = uptimeNanoseconds
    }

    var runtimeScheduler: ObservabilityRuntimeScheduler {
        ObservabilityRuntimeScheduler(
            nowMilliseconds: { self.currentWallMilliseconds },
            nowUptimeNanoseconds: { self.currentUptimeNanoseconds },
            sleep: { try await self.sleep(for: $0) }
        )
    }

    var currentWallMilliseconds: Int64 {
        locked { wallMilliseconds }
    }

    var currentUptimeNanoseconds: UInt64 {
        locked { uptimeNanoseconds }
    }

    func setTime(wallMilliseconds: Int64? = nil, uptimeNanoseconds: UInt64? = nil) {
        locked {
            if let wallMilliseconds { self.wallMilliseconds = wallMilliseconds }
            if let uptimeNanoseconds { self.uptimeNanoseconds = uptimeNanoseconds }
        }
    }

    func pendingSleepMilliseconds() -> [Int64] {
        locked { sleepers.map(\.duration.clampedMilliseconds) }
    }

    func cancelledSleepCount() -> Int {
        locked { cancellationCount }
    }

    @discardableResult
    func resumeFirstSleep(milliseconds: Int64) -> Bool {
        let continuation = locked { () -> CheckedContinuation<Void, Error>? in
            guard let index = sleepers.firstIndex(where: {
                $0.duration.clampedMilliseconds == milliseconds
            }) else { return nil }
            return sleepers.remove(at: index).continuation
        }
        continuation?.resume()
        return continuation != nil
    }

    private func sleep(for duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let shouldCancel = locked { () -> Bool in
                    if cancellationRequests.remove(id) != nil || Task.isCancelled {
                        cancellationCount += 1
                        return true
                    }
                    sleepers.append(Sleeper(id: id, duration: duration, continuation: continuation))
                    return false
                }
                if shouldCancel { continuation.resume(throwing: CancellationError()) }
            }
        } onCancel: {
            self.cancelSleep(id: id)
        }
    }

    private func cancelSleep(id: UUID) {
        let continuation = locked { () -> CheckedContinuation<Void, Error>? in
            guard let index = sleepers.firstIndex(where: { $0.id == id }) else {
                cancellationRequests.insert(id)
                return nil
            }
            cancellationCount += 1
            return sleepers.remove(at: index).continuation
        }
        continuation?.resume(throwing: CancellationError())
    }

    private func locked<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}

actor ObservabilityRuntimeSuspensionGate {
    private var entered = false
    private var open = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var openWaiters: [CheckedContinuation<Void, Never>] = []

    func enterAndWait() async {
        entered = true
        let waiters = enteredWaiters
        enteredWaiters.removeAll(keepingCapacity: false)
        waiters.forEach { $0.resume() }
        guard !open else { return }
        await withCheckedContinuation { openWaiters.append($0) }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func release() {
        guard !open else { return }
        open = true
        let waiters = openWaiters
        openWaiters.removeAll(keepingCapacity: false)
        waiters.forEach { $0.resume() }
    }
}

actor ObservabilityRuntimeCoreSpy: CoreObservabilityControlling {
    enum StartupCall: Equatable {
        case buildContext
        case initialize
    }

    struct Behavior: @unchecked Sendable {
        var failInitialization = false
        var failDisabledUpdate = false
        var failStandardUpdate = false
        var blockFirstModeUpdate = false
        var suspendFlush = false
        var failFlush = false
        var emitEventDuringFlush = false
        var reportedHealth = ObservabilityHealth.runtimeHealthy
    }

    enum SpyError: Error {
        case initialization
        case update
        case flush
    }

    private let behavior: Behavior
    private let updateGate = ObservabilityRuntimeSuspensionGate()
    private let flushGate = ObservabilityRuntimeSuspensionGate()
    private var initializationCount = 0
    private var startupCalls: [StartupCall] = []
    private var initializedConfigurations: [ObservabilityConfig] = []
    private var updatedConfigurations: [ObservabilityConfig] = []
    private var flushDeadlines: [UInt64] = []
    private var didBlockModeUpdate = false
    private var eventSink: (any CoreObservabilitySink)?

    init(behavior: Behavior = Behavior()) {
        self.behavior = behavior
    }

    func observabilityBuildContext() async -> ObservabilityBuildContextSnapshot {
        startupCalls.append(.buildContext)
        return observabilityTestCoreBuildContext()
    }

    func initializeObservability(
        config: ObservabilityConfig,
        sink: any CoreObservabilitySink
    ) async throws -> ObservabilityHealth {
        startupCalls.append(.initialize)
        initializationCount += 1
        initializedConfigurations.append(config)
        eventSink = sink
        if behavior.failInitialization { throw SpyError.initialization }
        return behavior.reportedHealth
    }

    func updateObservability(config: ObservabilityConfig) async throws -> ObservabilityHealth {
        updatedConfigurations.append(config)
        if behavior.blockFirstModeUpdate, config.mode != .disabled, !didBlockModeUpdate {
            didBlockModeUpdate = true
            await updateGate.enterAndWait()
        }
        if behavior.failDisabledUpdate, config.mode == .disabled { throw SpyError.update }
        if behavior.failStandardUpdate, config.mode == .standard { throw SpyError.update }
        return behavior.reportedHealth
    }

    func observabilityHealth() async -> ObservabilityHealth {
        behavior.reportedHealth
    }

    func flushObservability(deadlineMilliseconds: UInt64) async throws -> ObservabilityHealth {
        flushDeadlines.append(deadlineMilliseconds)
        if behavior.emitEventDuringFlush,
           let sessionID = initializedConfigurations.last?.sessionId {
            eventSink?.onEvent(event: runtimeCoreEvent(id: "flush-event", sessionID: sessionID))
        }
        if behavior.suspendFlush { await flushGate.enterAndWait() }
        if behavior.failFlush { throw SpyError.flush }
        return behavior.reportedHealth
    }

    func waitUntilModeUpdateEntered() async {
        await updateGate.waitUntilEntered()
    }

    func releaseModeUpdate() async {
        await updateGate.release()
    }

    func waitUntilFlushEntered() async {
        await flushGate.waitUntilEntered()
    }

    func releaseFlush() async {
        await flushGate.release()
    }

    func emit(_ event: CoreObservabilityEvent) {
        eventSink?.onEvent(event: event)
    }

    func initializeCallCount() -> Int {
        initializationCount
    }

    func recordedStartupCalls() -> [StartupCall] {
        startupCalls
    }

    func initializedModes() -> [ObservabilityMode] {
        initializedConfigurations.map(\.mode)
    }

    func updatedModes() -> [ObservabilityMode] {
        updatedConfigurations.map(\.mode)
    }

    func recordedFlushDeadlines() -> [UInt64] {
        flushDeadlines
    }
}

@MainActor
final class ObservabilityRuntimeFixture {
    let rootURL: URL
    let suiteName: String
    let defaults: UserDefaults
    let hub: ObservabilityHub
    let sessionRootURL: URL
    let runtime: ObservabilityRuntimeAssembly

    init(
        core: ObservabilityRuntimeCoreSpy,
        scheduler: TestObservabilityRuntimeScheduler,
        sessionID: String = "runtime-session"
    ) throws {
        rootURL = try makeTestTemporaryDirectory(named: "ObservabilityRuntimeTests")
        suiteName = "ObservabilityRuntimeTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        hub = ObservabilityHub(
            configurationStore: ObservabilityConfigurationStore(defaults: defaults),
            rootURL: rootURL.appendingPathComponent("Logs", isDirectory: true),
            sessionID: sessionID
        )
        sessionRootURL = rootURL.appendingPathComponent("Session", isDirectory: true)
        runtime = ObservabilityRuntimeAssembly(
            hub: hub,
            core: core,
            sessionStore: ObservabilitySessionLifecycleStore(rootURL: sessionRootURL),
            sessionID: sessionID,
            scheduler: scheduler.runtimeScheduler
        )
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
        removeTestTemporaryItems(rootURL)
    }

    func readSessionMarker() throws -> ObservabilitySessionMarker {
        let url = sessionRootURL.appendingPathComponent("session-marker.json", isDirectory: false)
        return try JSONDecoder().decode(ObservabilitySessionMarker.self, from: Data(contentsOf: url))
    }
}

@MainActor
func waitForRuntimeCondition(
    iterations: Int = 2000,
    _ condition: () async -> Bool
) async -> Bool {
    for _ in 0 ..< iterations {
        if await condition() { return true }
        await Task.yield()
    }
    return false
}

extension ObservabilityHealth {
    static let runtimeHealthy = Self(
        initialized: true,
        mode: .standard,
        queueDepth: 0,
        queueCapacity: 4096,
        droppedTrace: 0,
        droppedDebug: 0,
        droppedInfo: 0,
        droppedWarn: 0,
        droppedError: 0,
        redactionRejected: 0,
        callbackConnected: true,
        degraded: false,
        degradedReason: nil
    )
}

extension AppObservabilityConfiguration {
    static func runtimeMode(
        _ mode: AppObservabilityMode,
        lease: AppObservabilityModeLease? = nil
    ) -> Self {
        Self(
            mode: mode,
            minimumSeverity: mode == .developer ? .debug : .info,
            diskBudgetBytes: mode == .developer ? 512 * 1024 * 1024 : 250 * 1024 * 1024,
            retentionHours: 48,
            includeSensitive: false,
            modeLease: lease
        )
    }
}

func runtimeCoreEvent(id: String, sessionID: String) -> CoreObservabilityEvent {
    CoreObservabilityEvent(
        schemaVersion: 2,
        eventId: id,
        wallTimestampMs: 1,
        monotonicTimestampNs: 1,
        sequenceNumber: 1,
        sessionId: sessionID,
        incidentId: nil,
        traceId: "trace-\(id)",
        spanId: "span-\(id)",
        parentSpanId: nil,
        operationId: nil,
        retryOfOperationId: nil,
        actionId: "diagnostics.export.confirmed",
        componentId: "core.observability.runtime",
        layer: .core,
        phase: "event",
        severity: .info,
        outcome: .succeeded,
        durationMs: nil,
        resourceRefs: [],
        error: nil,
        attributes: [],
        privacyLevel: .public,
        message: nil,
        target: nil,
        threadName: "runtime-test",
        buildContext: ObservabilityBuildContext(
            producer: "area_matrix_core",
            version: "0.1.0",
            build: "test",
            configuration: "debug",
            platform: "macos",
            architecture: "aarch64"
        )
    )
}
