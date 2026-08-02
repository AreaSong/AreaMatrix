@testable import AreaMatrix
import Foundation
import XCTest

final class CoreObservabilitySinkAdapterTests: XCTestCase {
    func testAdapterMapsCoreEventAndDrainsAcceptedCallbacks() async throws {
        let probe = AdapterProbe()
        let adapter = makeAdapter(probe: probe, capacity: 4)

        adapter.onEvent(coreEvent(id: 7, includeDetails: true))
        await adapter.finishAndDrain()

        let snapshot = await probe.snapshot()
        let event = try XCTUnwrap(snapshot.events.first)
        XCTAssertEqual(snapshot.events.count, 1)
        XCTAssertEqual(snapshot.dropCount, 0)
        XCTAssertEqual(adapter.outstandingCount, 0)
        XCTAssertEqual(event.schemaVersion, 2)
        XCTAssertEqual(event.eventID, "event-7")
        XCTAssertEqual(event.sessionID, "session")
        XCTAssertEqual(event.incidentID, "incident")
        XCTAssertEqual(event.traceID, "trace")
        XCTAssertEqual(event.spanID, "span-7")
        XCTAssertEqual(event.parentSpanID, "parent")
        XCTAssertEqual(event.operationID, "operation")
        XCTAssertEqual(event.retryOfOperationID, "retry")
        XCTAssertEqual(event.actionID, "repository.import.validation")
        XCTAssertEqual(event.componentID, "core.storage.import")
        XCTAssertEqual(event.layer, "core")
        XCTAssertEqual(event.phase, "completed")
        XCTAssertEqual(event.severity, .warn)
        XCTAssertEqual(event.outcome, "failed")
        XCTAssertEqual(event.durationMilliseconds, 42)
        XCTAssertEqual(event.resources.first?.resourceID, "resource")
        XCTAssertEqual(event.error?.code, "test-error")
        XCTAssertEqual(event.attributes.first?.key, "attempt")
        XCTAssertEqual(event.privacy, "pseudonymous")
        XCTAssertEqual(event.message, "message")
        XCTAssertEqual(event.target, "target")
        XCTAssertEqual(event.threadName, "worker")
        XCTAssertEqual(event.buildContext?.producer, "area_matrix_core")
        XCTAssertEqual(event.buildContext?.version, "0.1.0")
        XCTAssertEqual(event.buildContext?.configuration, "debug")
        XCTAssertEqual(event.buildContext?.platform, "macos")
        XCTAssertEqual(event.buildContext?.architecture, "aarch64")
    }

    func testOverflowDropsOldestEqualPriorityEventAndDrainWaitsForDropAccounting() async {
        let probe = AdapterProbe(blocksFirstEvent: true)
        let adapter = makeAdapter(probe: probe, capacity: 1)

        adapter.onEvent(coreEvent(id: 1))
        await probe.waitUntilFirstEventEntered()
        adapter.onEvent(coreEvent(id: 2))
        adapter.onEvent(coreEvent(id: 3))
        await probe.waitUntilDropRecorded()

        let completion = AdapterCompletionCounter()
        let firstDrain = Task {
            await adapter.finishAndDrain()
            await completion.increment()
        }
        let secondDrain = Task {
            await adapter.finishAndDrain()
            await completion.increment()
        }
        await Task.yield()
        let completionCountBeforeRelease = await completion.value()
        XCTAssertEqual(completionCountBeforeRelease, 0)
        XCTAssertEqual(adapter.outstandingCount, 2)

        await probe.releaseFirstEvent()
        await firstDrain.value
        await secondDrain.value
        let snapshot = await probe.snapshot()
        let completionCountAfterDrain = await completion.value()
        XCTAssertEqual(snapshot.events.map(\.eventID), ["event-1", "event-3"])
        XCTAssertEqual(snapshot.dropCount, 1)
        XCTAssertEqual(completionCountAfterDrain, 2)
        XCTAssertEqual(adapter.outstandingCount, 0)
    }

    func testLowPriorityOverflowCannotDisplaceBufferedWarnOrErrorEvents() async {
        let probe = AdapterProbe(blocksFirstEvent: true)
        let adapter = makeAdapter(probe: probe, capacity: 2)

        adapter.onEvent(coreEvent(id: 1, severity: .info))
        await probe.waitUntilFirstEventEntered()
        adapter.onEvent(coreEvent(id: 2, severity: .error))
        adapter.onEvent(coreEvent(id: 3, severity: .warn))
        adapter.onEvent(coreEvent(id: 4, severity: .trace))

        await probe.releaseFirstEvent()
        await adapter.finishAndDrain()
        let snapshot = await probe.snapshot()

        XCTAssertEqual(snapshot.events.map(\.eventID), ["event-1", "event-2", "event-3"])
        XCTAssertEqual(snapshot.dropCount, 1)
        XCTAssertEqual(adapter.outstandingCount, 0)
    }

    func testTenThousandOverflowsUseOneReporterAndDrainAllAggregatedDrops() async {
        let probe = AdapterProbe(blocksFirstEvent: true, blocksFirstDropReport: true)
        let adapter = makeAdapter(probe: probe, capacity: 1)

        adapter.onEvent(coreEvent(id: 1))
        await probe.waitUntilFirstEventEntered()
        adapter.onEvent(coreEvent(id: 2))
        adapter.onEvent(coreEvent(id: 3))
        await probe.waitUntilDropReportEntered()

        for id in 4 ... 10003 {
            adapter.onEvent(coreEvent(id: id))
        }
        let blockedReport = await probe.snapshot()
        XCTAssertEqual(blockedReport.activeDropReportCount, 1)
        XCTAssertEqual(blockedReport.maximumDropReportCount, 1)

        let drain = Task { await adapter.finishAndDrain() }
        await Task.yield()
        await probe.releaseFirstEvent()
        await probe.releaseFirstDropReport()
        await drain.value
        let snapshot = await probe.snapshot()

        XCTAssertEqual(snapshot.events.map(\.eventID), ["event-1", "event-10003"])
        XCTAssertEqual(snapshot.dropCount, 10001)
        XCTAssertEqual(snapshot.maximumDropReportCount, 1)
        XCTAssertEqual(snapshot.activeDropReportCount, 0)
        XCTAssertEqual(adapter.outstandingCount, 0)
    }

    func testCallbackAfterCloseIsSynchronouslyIgnoredWithoutDropTask() async {
        let probe = AdapterProbe()
        let adapter = makeAdapter(probe: probe, capacity: 1)

        adapter.closeIngress()
        adapter.onEvent(coreEvent(id: 1))
        await adapter.finishAndDrain()

        let snapshot = await probe.snapshot()
        XCTAssertTrue(snapshot.events.isEmpty)
        XCTAssertEqual(snapshot.dropCount, 0)
        XCTAssertEqual(adapter.outstandingCount, 0)
    }

    func testConcurrentCallbacksAreDeliveredWithoutLossOrDuplicationWhenCapacityIsSufficient() async {
        let probe = AdapterProbe()
        let adapter = makeAdapter(probe: probe, capacity: 256)

        DispatchQueue.concurrentPerform(iterations: 200) { index in
            adapter.onEvent(coreEvent(id: index))
        }
        await adapter.finishAndDrain()

        let snapshot = await probe.snapshot()
        XCTAssertEqual(snapshot.events.count, 200)
        XCTAssertEqual(Set(snapshot.events.map(\.eventID)).count, 200)
        XCTAssertEqual(snapshot.dropCount, 0)
        XCTAssertEqual(adapter.outstandingCount, 0)
    }

    func testAdapterCanDeallocateWithoutExplicitDrain() async {
        let probe = AdapterProbe()
        weak var weakAdapter: CoreObservabilitySinkAdapter?

        do {
            let adapter = makeAdapter(probe: probe, capacity: 1)
            weakAdapter = adapter
        }
        await Task.yield()

        XCTAssertNil(weakAdapter)
    }

    private func makeAdapter(
        probe: AdapterProbe,
        capacity: Int
    ) -> CoreObservabilitySinkAdapter {
        CoreObservabilitySinkAdapter(
            capacity: capacity,
            ingest: { await probe.ingest($0) },
            noteIngressDrop: { await probe.noteDrop(count: $0) }
        )
    }
}

private struct AdapterProbeSnapshot {
    let events: [ObservabilityEventSnapshot]
    let dropCount: UInt64
    let activeDropReportCount: Int
    let maximumDropReportCount: Int
}

private actor AdapterProbe {
    private let blocksFirstEvent: Bool
    private let blocksFirstDropReport: Bool
    private let firstEventEntered = AdapterLatch()
    private let releaseFirst = AdapterLatch()
    private let firstDropRecorded = AdapterLatch()
    private let releaseFirstDrop = AdapterLatch()
    private var events: [ObservabilityEventSnapshot] = []
    private var dropCount: UInt64 = 0
    private var activeDropReportCount = 0
    private var maximumDropReportCount = 0
    private var didBlockDropReport = false

    init(blocksFirstEvent: Bool = false, blocksFirstDropReport: Bool = false) {
        self.blocksFirstEvent = blocksFirstEvent
        self.blocksFirstDropReport = blocksFirstDropReport
    }

    func ingest(_ event: ObservabilityEventSnapshot) async {
        events.append(event)
        guard blocksFirstEvent, events.count == 1 else { return }
        await firstEventEntered.open()
        await releaseFirst.wait()
    }

    func noteDrop(count: UInt64) async {
        activeDropReportCount += 1
        maximumDropReportCount = max(maximumDropReportCount, activeDropReportCount)
        let shouldBlock = blocksFirstDropReport && !didBlockDropReport
        didBlockDropReport = didBlockDropReport || shouldBlock
        await firstDropRecorded.open()
        if shouldBlock { await releaseFirstDrop.wait() }
        let (sum, overflow) = dropCount.addingReportingOverflow(count)
        dropCount = overflow ? .max : sum
        activeDropReportCount -= 1
    }

    func waitUntilFirstEventEntered() async {
        await firstEventEntered.wait()
    }

    func waitUntilDropRecorded() async {
        await firstDropRecorded.wait()
    }

    func releaseFirstEvent() async {
        await releaseFirst.open()
    }

    func waitUntilDropReportEntered() async {
        await firstDropRecorded.wait()
    }

    func releaseFirstDropReport() async {
        await releaseFirstDrop.open()
    }

    func snapshot() -> AdapterProbeSnapshot {
        AdapterProbeSnapshot(
            events: events,
            dropCount: dropCount,
            activeDropReportCount: activeDropReportCount,
            maximumDropReportCount: maximumDropReportCount
        )
    }
}

private actor AdapterCompletionCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}

private actor AdapterLatch {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let pending = waiters
        waiters.removeAll(keepingCapacity: false)
        pending.forEach { $0.resume() }
    }
}

private func coreEvent(
    id: Int,
    includeDetails: Bool = false,
    severity: AppObservabilitySeverity = .info
) -> ObservabilityEventSnapshot {
    ObservabilityEventSnapshot(
        schemaVersion: 2,
        eventID: "event-\(id)",
        wallTimestampMilliseconds: Int64(id),
        monotonicTimestampNanoseconds: UInt64(id),
        sequenceNumber: UInt64(id),
        sessionID: "session",
        incidentID: includeDetails ? "incident" : nil,
        traceID: "trace",
        spanID: "span-\(id)",
        parentSpanID: includeDetails ? "parent" : nil,
        operationID: includeDetails ? "operation" : nil,
        retryOfOperationID: includeDetails ? "retry" : nil,
        actionID: "repository.import.validation",
        componentID: "core.storage.import",
        layer: "core",
        phase: includeDetails ? "completed" : "event",
        severity: includeDetails ? .warn : severity,
        outcome: includeDetails ? "failed" : "succeeded",
        durationMilliseconds: includeDetails ? 42 : nil,
        resources: includeDetails ? [ObservabilityResourceSnapshot(
            resourceID: "resource",
            alias: "alias",
            pathExtension: "txt",
            sizeBucket: "small",
            storageMode: "copy"
        )] : [],
        error: includeDetails ? ObservabilityErrorSnapshot(
            code: "test-error",
            kind: "io",
            technicalDetails: "details"
        ) : nil,
        attributes: includeDetails ? [ObservabilityAttributeSnapshot(
            key: "attempt",
            value: "1",
            privacy: "public"
        )] : [],
        privacy: includeDetails ? "pseudonymous" : "public",
        message: includeDetails ? "message" : nil,
        target: includeDetails ? "target" : nil,
        threadName: includeDetails ? "worker" : nil,
        buildContext: ObservabilityBuildContextSnapshot(
            producer: "area_matrix_core",
            version: "0.1.0",
            build: nil,
            configuration: "debug",
            platform: "macos",
            architecture: "aarch64"
        )
    )
}
