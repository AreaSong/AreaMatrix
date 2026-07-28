@testable import AreaMatrix
import Foundation
import XCTest

final class DiagnosticsConsoleProjectionTests: XCTestCase {
    func testNineDimensionFilterAndClear() {
        let matching = makeEvent(
            id: "matching",
            sequence: 1,
            sessionID: "session-a",
            incidentID: "incident-a",
            traceID: "trace-a",
            operationID: "operation-a",
            actionID: "repository.import.completed",
            componentID: "core.repository.import",
            severity: .error,
            outcome: "failed",
            duration: 120
        )
        let other = makeEvent(id: "other", sequence: 2)
        let projection = DiagnosticsConsoleProjection(events: [other, matching])
        var filters = DiagnosticsFilterState(
            sessionID: "session-a",
            incidentID: "incident-a",
            traceID: "trace-a",
            operationID: "operation-a",
            actionID: "repository.import.completed",
            componentID: "core.repository.import",
            severity: .error,
            outcome: "failed",
            duration: .hundredToThousand
        )

        XCTAssertEqual(projection.filtered(using: filters).events.map(\.id), ["matching"])
        XCTAssertTrue(filters.isActive)

        filters.clear()

        XCTAssertFalse(filters.isActive)
        XCTAssertEqual(projection.filtered(using: filters).events.map(\.id), ["matching", "other"])
    }

    func testSpanTreeUsesParentOrderAndTerminatesCycles() {
        let root = makeEvent(id: "root", sequence: 3, spanID: "root")
        let child = makeEvent(id: "child", sequence: 1, spanID: "child", parentSpanID: "root")
        let leaf = makeEvent(id: "leaf", sequence: 2, spanID: "leaf", parentSpanID: "child")
        let ordered = DiagnosticsSpanTreeProjection.rows([leaf, child, root])

        XCTAssertEqual(ordered.map(\.id), ["root", "child", "leaf"])
        XCTAssertEqual(ordered.map(\.depth), [0, 1, 2])

        let cycleA = makeEvent(id: "cycle-a", sequence: 4, spanID: "a", parentSpanID: "b")
        let cycleB = makeEvent(id: "cycle-b", sequence: 5, spanID: "b", parentSpanID: "a")
        let cyclic = DiagnosticsSpanTreeProjection.rows([cycleB, cycleA])

        XCTAssertEqual(Set(cyclic.map(\.id)), Set(["cycle-a", "cycle-b"]))
        XCTAssertEqual(cyclic.count, 2)
        XCTAssertLessThanOrEqual(cyclic.map(\.depth).max() ?? 0, 1)
        XCTAssertTrue(cyclic.first?.isDetachedRoot == true)
    }

    func testStableSortUsesSequenceThenMonotonicThenFallbacks() {
        var late = makeEvent(id: "z", sequence: 4)
        late.monotonicTimestampNanoseconds = 20
        var early = makeEvent(id: "b", sequence: 4)
        early.monotonicTimestampNanoseconds = 10
        early.wallTimestampMilliseconds = 20
        var earliest = makeEvent(id: "a", sequence: 4)
        earliest.monotonicTimestampNanoseconds = 10
        earliest.wallTimestampMilliseconds = 10

        let result = DiagnosticsConsoleProjection(events: [late, early, earliest])
            .filtered(using: .init())

        XCTAssertEqual(result.events.map(\.id), ["a", "b", "z"])
    }

    func testRawJSONContainsCompleteEventAndUsesSafeFallback() throws {
        let event = makeSensitiveEvent()
        let encoded = DiagnosticsRawEncoder.encode(event)
        let decoded = try JSONDecoder().decode(
            ObservabilityEventSnapshot.self,
            from: XCTUnwrap(encoded.data(using: .utf8))
        )

        XCTAssertEqual(decoded, event)
        XCTAssertLessThan(
            try XCTUnwrap(encoded.range(of: "\"actionID\"")).lowerBound,
            try XCTUnwrap(encoded.range(of: "\"attributes\"")).lowerBound
        )

        let fallback = DiagnosticsRawEncoder.encode(event) { _ in throw EncodingFailure.expected }
        let fallbackObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: XCTUnwrap(fallback.data(using: .utf8))) as? [String: Any]
        )
        XCTAssertEqual(fallbackObject["encodingError"] as? Bool, true)
        XCTAssertEqual(fallbackObject["eventID"] as? String, event.eventID)
        XCTAssertFalse(fallback.contains(event.message ?? "sensitive-message"))
    }

    func testFingerprintIgnoresSensitivePresentationFields() {
        let original = makeSensitiveEvent()
        var changed = original
        changed.message = "another private message"
        changed.attributes[0].value = "another secret"
        changed.resources[0].alias = "private-alias"
        changed.resources[0].resourceID = "different-resource-id"
        changed.error?.technicalDetails = "private stack trace"
        changed.target = "/private/path"

        XCTAssertEqual(
            DiagnosticsFingerprint.make(events: [original]),
            DiagnosticsFingerprint.make(events: [changed])
        )

        changed.error?.code = "different.code"
        XCTAssertNotEqual(
            DiagnosticsFingerprint.make(events: [original]),
            DiagnosticsFingerprint.make(events: [changed])
        )
    }

    func testFingerprintIncludesNormalizedParentChildStructure() {
        let root = makeEvent(id: "root", sequence: 1, spanID: "root")
        let child = makeEvent(id: "child", sequence: 2, spanID: "child", parentSpanID: "root")
        var detached = child
        detached.parentSpanID = nil

        XCTAssertNotEqual(
            DiagnosticsFingerprint.make(events: [root, child]),
            DiagnosticsFingerprint.make(events: [root, detached])
        )
    }

    func testTerminalLineContainsRequiredOperationalIdentity() throws {
        let event = makeSensitiveEvent()
        let line = try XCTUnwrap(
            DiagnosticsConsoleProjection(events: [event]).filtered(using: .init()).events.first
        ).terminalLine

        for field in ["session=", "incident=", "operation=", "retry=", "resources=", "error=", "duration_ms="] {
            XCTAssertTrue(line.contains(field), "Missing terminal field: \(field)")
        }
        XCTAssertEqual(line.components(separatedBy: .newlines).count, 1)
    }

    func testTraceDiffPreservesDuplicateOccurrencesAndStableOrder() {
        let baseline = [
            makeEvent(id: "baseline-validation-1", sequence: 1, actionID: "validation"),
            makeEvent(id: "baseline-validation-2", sequence: 2, actionID: "validation"),
            makeEvent(id: "baseline-staging", sequence: 3, actionID: "staging")
        ]
        let comparison = [
            makeEvent(id: "comparison-validation", sequence: 1, actionID: "validation"),
            makeEvent(id: "comparison-staging", sequence: 2, actionID: "staging"),
            makeEvent(id: "comparison-overview", sequence: 3, actionID: "overview")
        ]

        let diff = DiagnosticsTraceDiffProjection.compare(
            baseline: baseline,
            comparison: comparison
        )

        XCTAssertEqual(diff.onlyBaseline, ["validation|macos.ui|completed|succeeded|-#2"])
        XCTAssertEqual(diff.shared, [
            "validation|macos.ui|completed|succeeded|-#1",
            "staging|macos.ui|completed|succeeded|-#1"
        ])
        XCTAssertEqual(diff.onlyComparison, ["overview|macos.ui|completed|succeeded|-#1"])
    }

    func testTraceRevisionTokenChangesWhenSemanticEventChanges() {
        let original = makeEvent(id: "stable", sequence: 1)
        let originalToken = DiagnosticsConsoleProjection(events: [original])
            .filtered(using: .init()).traceRevisionToken
        var variants: [ObservabilityEventSnapshot] = []
        var action = original
        action.actionID = "changed.action"
        variants.append(action)
        var component = original
        component.componentID = "changed.component"
        variants.append(component)
        var phase = original
        phase.phase = "started"
        variants.append(phase)
        var outcome = original
        outcome.outcome = "failed"
        variants.append(outcome)
        var error = original
        error.error = .init(code: "changed.error", kind: nil, technicalDetails: nil)
        variants.append(error)

        for variant in variants {
            let changedToken = DiagnosticsConsoleProjection(events: [variant])
                .filtered(using: .init()).traceRevisionToken
            XCTAssertNotEqual(changedToken, originalToken)
        }
    }
}

private enum EncodingFailure: Error {
    case expected
}

private func makeEvent(
    id: String,
    sequence: UInt64,
    sessionID: String = "session-default",
    incidentID: String? = nil,
    traceID: String = "trace-default",
    spanID: String? = nil,
    parentSpanID: String? = nil,
    operationID: String? = nil,
    actionID: String = "app.command.recorded",
    componentID: String = "macos.ui",
    severity: AppObservabilitySeverity = .info,
    outcome: String = "succeeded",
    duration: UInt64? = 5
) -> ObservabilityEventSnapshot {
    ObservabilityEventSnapshot(
        schemaVersion: 1,
        eventID: id,
        wallTimestampMilliseconds: Int64(sequence),
        monotonicTimestampNanoseconds: sequence,
        sequenceNumber: sequence,
        sessionID: sessionID,
        incidentID: incidentID,
        traceID: traceID,
        spanID: spanID ?? "span-\(id)",
        parentSpanID: parentSpanID,
        operationID: operationID,
        retryOfOperationID: nil,
        actionID: actionID,
        componentID: componentID,
        layer: "test",
        phase: "completed",
        severity: severity,
        outcome: outcome,
        durationMilliseconds: duration,
        resources: [],
        error: nil,
        attributes: [],
        privacy: "public",
        message: nil,
        target: nil,
        threadName: "test-thread"
    )
}

private func makeSensitiveEvent() -> ObservabilityEventSnapshot {
    var event = makeEvent(
        id: "sensitive-event",
        sequence: 9,
        sessionID: "session-sensitive",
        incidentID: "incident-sensitive",
        traceID: "trace-sensitive",
        operationID: "operation-sensitive",
        actionID: "repository.import.failed",
        componentID: "core.repository.import",
        severity: .error,
        outcome: "failed",
        duration: 450
    )
    event.retryOfOperationID = "operation-before"
    event.resources = [.init(
        resourceID: "resource-stable",
        alias: "secret-file-name.txt",
        pathExtension: "txt",
        sizeBucket: "small",
        storageMode: "local"
    )]
    event.error = .init(code: "import.failed", kind: "io", technicalDetails: "secret detail")
    event.attributes = [.init(key: "source.name", value: "secret-value", privacy: "sensitive")]
    event.privacy = "sensitive"
    event.message = "sensitive-message"
    event.target = "/private/target"
    return event
}
