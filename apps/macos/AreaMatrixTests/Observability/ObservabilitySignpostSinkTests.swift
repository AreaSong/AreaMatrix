import AppKit
@testable import AreaMatrix
import XCTest

final class ObservabilitySignpostSinkTests: XCTestCase {
    func testSignpostPairsAllowlistedIntervalExactlyOnce() {
        let recorder = SignpostRecorderSpy()
        let sink = ObservabilitySignpostSink(recorder: recorder, maximumActiveIntervals: 2)

        sink.consume(signpostEvent(phase: "started"))
        sink.consume(signpostEvent(phase: "completed"))

        XCTAssertEqual(recorder.calls(), [
            .init(
                kind: .begin,
                registration: .importValidation,
                key: "session:span:repository.import.validation"
            ),
            .init(
                kind: .end,
                registration: .importValidation,
                key: "session:span:repository.import.validation"
            )
        ])
        XCTAssertEqual(sink.health(), .init(activeIntervalCount: 0, rejectedIntervalCount: 0))
    }

    func testDuplicateResolutionUsesTheRegisteredDedupComponent() {
        let recorder = SignpostRecorderSpy()
        let sink = ObservabilitySignpostSink(recorder: recorder)

        sink.consume(signpostEvent(
            actionID: "repository.import.duplicate_resolution",
            componentID: "core.storage.dedup",
            phase: "started"
        ))
        sink.consume(signpostEvent(
            actionID: "repository.import.duplicate_resolution",
            componentID: "core.storage.dedup",
            phase: "completed"
        ))

        XCTAssertEqual(recorder.calls(), [
            .init(
                kind: .begin,
                registration: .importDuplicateResolution,
                key: "session:span:repository.import.duplicate_resolution"
            ),
            .init(
                kind: .end,
                registration: .importDuplicateResolution,
                key: "session:span:repository.import.duplicate_resolution"
            )
        ])
    }

    func testSignpostCorrelationUsesExactRegistrationAndStableIdentity() throws {
        let event = signpostEvent(phase: "started")

        let correlation = try XCTUnwrap(ObservabilitySignpostSink.correlation(for: event))

        XCTAssertEqual(correlation.registration, .importValidation)
        XCTAssertEqual(correlation.category, "RegisteredPerformance")
        XCTAssertEqual(correlation.spanID, "span")
        XCTAssertEqual(correlation.correlationKey, "session:span:repository.import.validation")
        XCTAssertNil(ObservabilitySignpostSink.correlation(for: signpostEvent(
            componentID: "core.storage.dedup",
            phase: "started"
        )))
    }

    func testSignpostIgnoresUnknownAndRejectsUnpairedDuplicateAndOverCapacityIntervals() {
        let recorder = SignpostRecorderSpy()
        let sink = ObservabilitySignpostSink(recorder: recorder, maximumActiveIntervals: 1)

        sink.consume(signpostEvent(actionID: "unknown.action", phase: "started"))
        sink.consume(signpostEvent(phase: "completed", spanID: "missing"))
        sink.consume(signpostEvent(phase: "started", spanID: "one"))
        sink.consume(signpostEvent(phase: "started", spanID: "one"))
        sink.consume(signpostEvent(phase: "started", spanID: "two"))
        sink.consume(signpostEvent(phase: "completed", spanID: "one"))

        XCTAssertEqual(recorder.calls(), [
            .init(
                kind: .begin,
                registration: .importValidation,
                key: "session:one:repository.import.validation"
            ),
            .init(
                kind: .end,
                registration: .importValidation,
                key: "session:one:repository.import.validation"
            )
        ])
        XCTAssertEqual(sink.health(), .init(activeIntervalCount: 0, rejectedIntervalCount: 3))
    }
}

private func signpostEvent(
    actionID: String = "repository.import.validation",
    componentID: String = "core.storage.import",
    phase: String,
    spanID: String = "span"
) -> ObservabilityEventSnapshot {
    ObservabilityEventSnapshot(
        schemaVersion: 1,
        eventID: UUID().uuidString,
        wallTimestampMilliseconds: 1,
        monotonicTimestampNanoseconds: 1,
        sequenceNumber: 1,
        sessionID: "session",
        incidentID: nil,
        traceID: "trace",
        spanID: spanID,
        parentSpanID: nil,
        operationID: nil,
        retryOfOperationID: nil,
        actionID: actionID,
        componentID: componentID,
        layer: "core",
        phase: phase,
        severity: .info,
        outcome: "succeeded",
        durationMilliseconds: nil,
        resources: [],
        error: nil,
        attributes: [],
        privacy: "public",
        message: nil,
        target: nil,
        threadName: nil
    )
}
