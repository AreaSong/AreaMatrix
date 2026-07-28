@testable import AreaMatrix
import Foundation
import XCTest

final class ObservabilityPerformanceTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        guard ProcessInfo.processInfo.environment["AREAMATRIX_RUN_PERF_TESTS"] == "1" else {
            throw XCTSkip("Observability performance tests use the explicit performance gate.")
        }
    }

    func testSourceSanitizationThroughput() throws {
        let catalog = try ObservabilityCatalog.loadBundled().get()
        let event = contractEvent(id: "sanitize", sessionID: "performance-session")
        var accepted = 0

        let elapsed = measureClock {
            for _ in 0 ..< 10000 {
                let sanitized = ObservabilityHubPolicy.sanitize(
                    event,
                    includeSensitive: false,
                    catalog: catalog,
                    buildScope: .diagnosticPackage
                )
                accepted += sanitized == nil ? 0 : 1
            }
        }

        XCTAssertEqual(accepted, 10000)
        XCTAssertLessThan(elapsed, .seconds(2))
    }

    func testBoundedRingSustainedThroughput() {
        let event = contractEvent(id: "ring", sessionID: "performance-session")
        var ring = ObservabilityEventRing()

        let elapsed = measureClock {
            for _ in 0 ..< 200_000 {
                ring.append(event, capacity: 50000)
            }
        }

        XCTAssertEqual(ring.count, 50000)
        XCTAssertLessThan(elapsed, .seconds(2))
    }

    func testRollingStoreThroughputAndRotation() throws {
        let root = try makeTestTemporaryDirectory(named: #function)
        defer { removeTestTemporaryItems(root) }
        let configuration = contractConfiguration(mode: .developer)
        var store = RollingObservabilityStore(
            rootURL: root,
            rotationBytesOverride: 32 * 1024
        )
        try store.prepare(configuration: configuration)

        let elapsed = try measureClock {
            for index in 0 ..< 500 {
                try store.append(
                    contractEvent(
                        id: "store-\(index)",
                        timestamp: Int64(index + 1),
                        sessionID: "performance-session",
                        message: "bounded rolling store performance payload"
                    ),
                    configuration: configuration
                )
            }
            try store.flush()
        }
        let eventFiles = try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0.hasPrefix("events-") && $0.hasSuffix(".jsonl") }

        XCTAssertGreaterThan(eventFiles.count, 1)
        XCTAssertLessThan(elapsed, .seconds(5))
    }

    func testTraceConsoleLargeDatasetProjection() {
        let events = makeConsoleEvents(count: 10000, traceWidth: 100)
        var result = DiagnosticsFilteredProjection.empty

        let elapsed = measureClock {
            result = DiagnosticsConsoleProjection(events: events).filtered(using: .init())
        }

        XCTAssertEqual(result.events.count, 10000)
        XCTAssertEqual(result.traceIDs.count, 100)
        XCTAssertTrue(result.traces.values.allSatisfy { $0.treeRows.count == 100 })
        XCTAssertLessThan(elapsed, .seconds(10))
    }
}

private extension ObservabilityPerformanceTests {
    func makeConsoleEvents(count: Int, traceWidth: Int) -> [ObservabilityEventSnapshot] {
        (0 ..< count).map { index in
            let traceIndex = index / traceWidth
            let spanIndex = index % traceWidth
            var event = contractEvent(
                id: "console-\(index)",
                timestamp: Int64(index + 1),
                sessionID: "performance-session"
            )
            event.traceID = "trace-\(traceIndex)"
            event.operationID = "operation-\(traceIndex)"
            event.spanID = "span-\(traceIndex)-\(spanIndex)"
            event.parentSpanID = spanIndex == 0
                ? nil
                : "span-\(traceIndex)-\(spanIndex - 1)"
            return event
        }
    }

    func measureClock(_ operation: () throws -> Void) rethrows -> Duration {
        let clock = ContinuousClock()
        let start = clock.now
        try operation()
        return start.duration(to: clock.now)
    }
}
