@testable import AreaMatrix
import Foundation
import XCTest

final class DiagnosticsExpectedActualProjectionTests: XCTestCase {
    func testOperationEvidenceMergesAcrossTraceIDs() throws {
        let catalog = try ObservabilityCatalog.loadBundled().get()
        let events = [
            makeFlowEvent(
                id: "entry",
                sequence: 1,
                traceID: "trace-a",
                actionID: "repository.import.confirmed",
                componentID: "macos.import.batch",
                phase: "started"
            ),
            makeFlowEvent(
                id: "validation",
                sequence: 2,
                traceID: "trace-b",
                actionID: "repository.import.validation",
                componentID: "core.storage.import",
                phase: "completed"
            )
        ]
        let result = DiagnosticsConsoleProjection(events: events, catalog: catalog).filtered(using: .init())

        for traceID in ["trace-a", "trace-b"] {
            let operation = try XCTUnwrap(result.traces[traceID]?.operations["operation-a"])
            XCTAssertEqual(operation.events.map(\.id), ["entry", "validation"])
        }
    }

    func testRetryUsesANewOperationWithoutMergingEvidence() throws {
        let first = makeFlowEvent(id: "first", sequence: 1, operationID: "operation-a")
        let retry = makeFlowEvent(
            id: "retry",
            sequence: 2,
            operationID: "operation-b",
            retryOfOperationID: "operation-a"
        )
        let trace = try XCTUnwrap(
            DiagnosticsConsoleProjection(events: [first, retry])
                .filtered(using: .init())
                .traces["trace-a"]
        )

        XCTAssertEqual(trace.operationIDs, ["operation-a", "operation-b"])
        XCTAssertEqual(trace.operations["operation-a"]?.events.map(\.id), ["first"])
        XCTAssertEqual(trace.operations["operation-b"]?.events.map(\.id), ["retry"])
    }

    func testNilOperationDoesNotFallBackToTraceIdentity() throws {
        let event = makeFlowEvent(id: "no-operation", sequence: 1, operationID: nil)
        let trace = try XCTUnwrap(
            DiagnosticsConsoleProjection(events: [event])
                .filtered(using: .init())
                .traces["trace-a"]
        )

        XCTAssertTrue(trace.operationIDs.isEmpty)
        XCTAssertTrue(trace.operations.isEmpty)
    }

    func testSelectorsUseExactIdentityAndWildcardPhase() throws {
        let catalog = try ObservabilityCatalog.loadBundled().get()
        let events = [
            makeFlowEvent(
                id: "entry",
                sequence: 1,
                actionID: "repository.import.confirmed",
                componentID: "macos.import.batch",
                phase: "started"
            ),
            makeFlowEvent(
                id: "group",
                sequence: 2,
                actionID: "repository.import.validation",
                componentID: "core.repository.import",
                phase: "started"
            ),
            makeFlowEvent(
                id: "wildcard",
                sequence: 3,
                actionID: "repository.import.validation",
                componentID: "core.storage.import",
                phase: "custom"
            ),
            makeFlowEvent(
                id: "prefix",
                sequence: 4,
                actionID: "repository.import.validation.extra",
                componentID: "core.storage.import",
                phase: "completed"
            ),
            makeFlowEvent(
                id: "wrong-phase",
                sequence: 5,
                actionID: "repository.import.confirmed",
                componentID: "core.repository.import",
                phase: "started.extra"
            )
        ]
        let projection = DiagnosticsExpectedActualProjection.make(
            operationID: "operation-a",
            events: events,
            catalog: catalog
        )

        XCTAssertEqual(row("ui.started", in: projection)?.matchedEventID, "entry")
        XCTAssertEqual(row("core.started", in: projection)?.matchedEventID, "group")
        XCTAssertEqual(row("validation", in: projection)?.matchedEventID, "wildcard")
        XCTAssertEqual(actual("prefix", in: projection)?.matchedStepIDs, [])
        XCTAssertEqual(actual("wrong-phase", in: projection)?.matchedStepIDs, [])
    }

    func testRequiredAndOptionalMissingStepsRemainDistinct() throws {
        let catalog = try ObservabilityCatalog.loadBundled().get()
        let entry = makeFlowEvent(
            id: "entry",
            sequence: 1,
            actionID: "repository.import.confirmed",
            componentID: "macos.import.batch",
            phase: "started"
        )
        let projection = DiagnosticsExpectedActualProjection.make(
            operationID: "operation-a",
            events: [entry],
            catalog: catalog
        )

        XCTAssertEqual(row("core.started", in: projection)?.required, true)
        XCTAssertNil(row("core.started", in: projection)?.matchedEventID)
        XCTAssertEqual(row("ui.completed", in: projection)?.required, false)
        XCTAssertNil(row("ui.completed", in: projection)?.matchedEventID)
    }

    func testOneEventCanMatchMultipleExpectedSteps() throws {
        let catalog = try makeMultiFlowCatalog()
        let events = [
            makeFlowEvent(id: "entry", sequence: 1, actionID: "flow.alpha.entry"),
            makeFlowEvent(id: "shared", sequence: 2, actionID: "flow.shared.step")
        ]
        let projection = DiagnosticsExpectedActualProjection.make(
            operationID: "operation-a",
            events: events,
            catalog: catalog
        )

        XCTAssertEqual(actual("shared", in: projection)?.matchedStepIDs, ["shared.one", "shared.two"])
    }

    func testFilterChangesVisibilityWithoutCroppingOperationEvidence() throws {
        let catalog = try ObservabilityCatalog.loadBundled().get()
        let events = [
            makeFlowEvent(
                id: "entry",
                sequence: 1,
                actionID: "repository.import.confirmed",
                componentID: "macos.import.batch",
                phase: "started"
            ),
            makeFlowEvent(
                id: "validation",
                sequence: 2,
                actionID: "repository.import.validation",
                componentID: "core.storage.import",
                phase: "completed"
            )
        ]
        let filtered = DiagnosticsConsoleProjection(events: events, catalog: catalog).filtered(using: .init(
            actionID: "repository.import.validation"
        ))
        let operation = try XCTUnwrap(filtered.traces["trace-a"]?.operations["operation-a"])

        XCTAssertEqual(filtered.events.map(\.id), ["validation"])
        XCTAssertEqual(operation.events.map(\.id), ["entry", "validation"])
        XCTAssertEqual(row("ui.started", in: operation.expectedActual)?.matchedEventID, "entry")
        XCTAssertEqual(row("validation", in: operation.expectedActual)?.matchedEventID, "validation")
    }

    func testLegacyPackageDoesNotUseCurrentCatalogForVerdict() throws {
        let catalog = try ObservabilityCatalog.loadBundled().get()
        let projection = DiagnosticsExpectedActualProjection.make(
            operationID: "operation-a",
            events: [makeFlowEvent(id: "entry", sequence: 1)],
            catalog: catalog,
            evaluationContext: .legacyPackage
        )

        XCTAssertEqual(projection.state, .legacyPackage)
        XCTAssertNil(projection.flowID)
        XCTAssertTrue(projection.expected.isEmpty)
        XCTAssertTrue(projection.actual.isEmpty)
    }

    func testMultipleEntryActionsReportAmbiguousFlow() throws {
        let catalog = try makeMultiFlowCatalog()
        let projection = DiagnosticsExpectedActualProjection.make(
            operationID: "operation-a",
            events: [
                makeFlowEvent(id: "alpha", sequence: 1, actionID: "flow.alpha.entry"),
                makeFlowEvent(id: "beta", sequence: 2, actionID: "flow.beta.entry")
            ],
            catalog: catalog
        )

        XCTAssertEqual(projection.state, .ambiguousFlow)
        XCTAssertEqual(projection.actual.map(\.id), ["alpha", "beta"])
    }
}

private func row(
    _ id: String,
    in projection: DiagnosticsExpectedActualProjection
) -> DiagnosticsExpectedStepRow? {
    projection.expected.first { $0.id == id }
}

private func actual(
    _ id: String,
    in projection: DiagnosticsExpectedActualProjection
) -> DiagnosticsActualEventRow? {
    projection.actual.first { $0.id == id }
}

private func makeFlowEvent(
    id: String,
    sequence: UInt64,
    traceID: String = "trace-a",
    operationID: String? = "operation-a",
    retryOfOperationID: String? = nil,
    actionID: String = "repository.import.confirmed",
    componentID: String = "core.flow.worker",
    phase: String = "started"
) -> ObservabilityEventSnapshot {
    ObservabilityEventSnapshot(
        schemaVersion: 2,
        eventID: id,
        wallTimestampMilliseconds: Int64(sequence),
        monotonicTimestampNanoseconds: sequence,
        sequenceNumber: sequence,
        sessionID: "session-a",
        incidentID: nil,
        traceID: traceID,
        spanID: "span-\(id)",
        parentSpanID: nil,
        operationID: operationID,
        retryOfOperationID: retryOfOperationID,
        actionID: actionID,
        componentID: componentID,
        layer: "test",
        phase: phase,
        severity: .info,
        outcome: "succeeded",
        durationMilliseconds: 1,
        resources: [],
        error: nil,
        attributes: [],
        privacy: "public",
        message: nil,
        target: nil,
        threadName: "test-thread"
    )
}

private func makeMultiFlowCatalog() throws -> ObservabilityCatalog {
    try ObservabilityCatalog.decode(Data(multiFlowCatalogDocument.utf8))
}

private let multiFlowCatalogDocument = """
    {
      "schema_version": 1,
      "actions": [
        {"id":"flow.alpha.entry","group":"flow.alpha"},
        {"id":"flow.beta.entry","group":"flow.beta"},
        {"id":"flow.shared.step","group":"flow.shared"}
      ],
      "components": [
        {
          "id":"core.flow.worker",
          "owner":"core",
          "role":"runtime",
          "symbol":"Core.FlowWorker",
          "authority":"docs/development/observability.md"
        }
      ],
      "expected_flows": [
        {
          "id":"flow.alpha",
          "entry_action_ids":["flow.alpha.entry"],
          "steps":[
            {
              "id":"alpha.entry",
              "required":true,
              "match_any":[{
                "action_id":"flow.alpha.entry",
                "component_id":"core.flow.worker",
                "phase":"started"
              }]
            },
            {
              "id":"shared.one",
              "required":false,
              "match_any":[{
                "action_id":"flow.shared.step",
                "component_id":"core.flow.worker"
              }]
            },
            {
              "id":"shared.two",
              "required":false,
              "match_any":[{
                "action_id":"flow.shared.step",
                "component_id":"core.flow.worker"
              }]
            }
          ]
        },
        {
          "id":"flow.beta",
          "entry_action_ids":["flow.beta.entry"],
          "steps":[{
            "id":"beta.entry",
            "required":true,
            "match_any":[{
              "action_id":"flow.beta.entry",
              "component_id":"core.flow.worker",
              "phase":"started"
            }]
          }]
        }
      ]
    }
"""
