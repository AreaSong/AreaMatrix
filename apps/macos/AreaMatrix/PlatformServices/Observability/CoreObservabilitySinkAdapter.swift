import Foundation

final class CoreObservabilitySinkAdapter: CoreObservabilitySink, @unchecked Sendable {
    private let deliverySignal: AsyncStream<Void>.Continuation
    private let dropSignal: AsyncStream<Void>.Continuation
    private let consumerTask: Task<Void, Never>
    private let dropReporterTask: Task<Void, Never>
    private let state: CoreObservabilityAdapterState

    convenience init(hub: ObservabilityHub, capacity: Int = 4096) {
        self.init(
            capacity: capacity,
            ingest: { await hub.ingestCoreEvent($0) },
            noteIngressDrop: { await hub.noteIngressDrop(count: $0) }
        )
    }

    init(
        capacity: Int = 4096,
        ingest: @escaping @Sendable (ObservabilityEventSnapshot) async -> Void,
        noteIngressDrop: @escaping @Sendable (UInt64) async -> Void
    ) {
        let deliveryPair = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let dropPair = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let state = CoreObservabilityAdapterState(capacity: capacity)

        self.state = state
        deliverySignal = deliveryPair.continuation
        dropSignal = dropPair.continuation
        consumerTask = Task {
            for await _ in deliveryPair.stream {
                while let event = state.dequeue() {
                    await ingest(event)
                    state.finishDelivery()
                }
            }
            while let event = state.dequeue() {
                await ingest(event)
                state.finishDelivery()
            }
        }
        dropReporterTask = Task {
            for await _ in dropPair.stream {
                await Self.reportPendingDrops(state: state, report: noteIngressDrop)
            }
            await Self.reportPendingDrops(state: state, report: noteIngressDrop)
        }
    }

    deinit {
        deliverySignal.finish()
        dropSignal.finish()
    }

    func onEvent(event: CoreObservabilityEvent) {
        let result = state.enqueue(ObservabilityEventSnapshot(coreEvent: event))
        if result.shouldWakeConsumer { deliverySignal.yield(()) }
        if result.recordedDrop { dropSignal.yield(()) }
    }

    func finishAndDrain() async {
        closeIngress()
        await consumerTask.value
        await dropReporterTask.value
    }

    func closeIngress() {
        guard state.closeIngress() else { return }
        deliverySignal.finish()
        dropSignal.finish()
    }

    var outstandingCount: Int {
        state.outstandingCount
    }
}

private extension CoreObservabilitySinkAdapter {
    static func reportPendingDrops(
        state: CoreObservabilityAdapterState,
        report: @Sendable (UInt64) async -> Void
    ) async {
        while true {
            let count = state.takePendingDropCount()
            guard count > 0 else { return }
            await report(count)
        }
    }
}

private final class CoreObservabilityAdapterState: @unchecked Sendable {
    struct EnqueueResult {
        let shouldWakeConsumer: Bool
        let recordedDrop: Bool

        static let rejected = Self(shouldWakeConsumer: false, recordedDrop: false)
    }

    private let lock = NSLock()
    private let capacity: Int
    private var accepting = true
    private var queue: [ObservabilityEventSnapshot] = []
    private var outstanding = 0
    private var pendingDropCount: UInt64 = 0

    init(capacity: Int) {
        self.capacity = max(1, capacity)
        queue.reserveCapacity(self.capacity)
    }

    func enqueue(_ event: ObservabilityEventSnapshot) -> EnqueueResult {
        lock.withLock {
            guard accepting else { return .rejected }
            guard queue.count >= capacity else {
                queue.append(event)
                outstanding += 1
                return EnqueueResult(shouldWakeConsumer: true, recordedDrop: false)
            }

            let lowestRank = queue.lazy.map(\.severity.rank).min() ?? event.severity.rank
            guard event.severity.rank >= lowestRank,
                  let replacementIndex = queue.firstIndex(where: { $0.severity.rank == lowestRank })
            else {
                recordDrop()
                return EnqueueResult(shouldWakeConsumer: false, recordedDrop: true)
            }

            queue.remove(at: replacementIndex)
            queue.append(event)
            recordDrop()
            return EnqueueResult(shouldWakeConsumer: true, recordedDrop: true)
        }
    }

    func dequeue() -> ObservabilityEventSnapshot? {
        lock.withLock {
            guard !queue.isEmpty else { return nil }
            return queue.removeFirst()
        }
    }

    func finishDelivery() {
        lock.withLock {
            if outstanding > 0 { outstanding -= 1 }
        }
    }

    func closeIngress() -> Bool {
        lock.withLock {
            guard accepting else { return false }
            accepting = false
            return true
        }
    }

    func takePendingDropCount() -> UInt64 {
        lock.withLock {
            let count = pendingDropCount
            pendingDropCount = 0
            return count
        }
    }

    var outstandingCount: Int {
        lock.withLock { outstanding }
    }

    private func recordDrop() {
        if pendingDropCount < .max { pendingDropCount += 1 }
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
