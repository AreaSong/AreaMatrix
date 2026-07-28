import Foundation

enum DiagnosticsExpectedActualState: Equatable {
    case ready
    case ambiguousFlow
    case catalogUnavailable
    case flowUnavailable
    case legacyPackage
    case operationRequired
}

enum DiagnosticsFlowEvaluationContext: Equatable {
    case current
    case legacyPackage
}

struct DiagnosticsExpectedStepRow: Identifiable, Equatable {
    var id: String {
        stepID
    }

    let stepID: String
    let value: String
    let required: Bool
    let matchedEventID: String?
}

struct DiagnosticsActualEventRow: Identifiable, Equatable {
    let id: String
    let value: String
    let matchedStepIDs: [String]
}

struct DiagnosticsExpectedActualProjection: Equatable {
    let operationID: String?
    let flowID: String?
    let state: DiagnosticsExpectedActualState
    let expected: [DiagnosticsExpectedStepRow]
    let actual: [DiagnosticsActualEventRow]

    static let operationRequired = Self(
        operationID: nil,
        flowID: nil,
        state: .operationRequired,
        expected: [],
        actual: []
    )

    static func make(
        operationID: String,
        events: [ObservabilityEventSnapshot],
        catalog: ObservabilityCatalog?,
        evaluationContext: DiagnosticsFlowEvaluationContext = .current
    ) -> Self {
        guard evaluationContext == .current else {
            return unavailable(operationID: operationID, state: .legacyPackage)
        }
        guard let catalog else {
            return unavailable(operationID: operationID, state: .catalogUnavailable)
        }
        let operationEvents = events
            .filter { $0.operationID == operationID }
            .sorted(by: DiagnosticsEventOrdering.areInIncreasingOrder)
        let matchingFlows = catalog.expectedFlows.filter { flow in
            operationEvents.contains { flow.entryActionIDs.contains($0.actionID) }
        }
        guard matchingFlows.count <= 1 else {
            return unavailable(operationID: operationID, state: .ambiguousFlow, events: operationEvents)
        }
        guard let flow = matchingFlows.first else {
            return unavailable(operationID: operationID, state: .flowUnavailable, events: operationEvents)
        }
        return evaluated(operationID: operationID, events: operationEvents, flow: flow, catalog: catalog)
    }

    private static func evaluated(
        operationID: String,
        events: [ObservabilityEventSnapshot],
        flow: ObservabilityCatalog.ExpectedFlow,
        catalog: ObservabilityCatalog
    ) -> Self {
        let expected = flow.steps.map { step in
            let matchedIndex = events.indices.first { index in
                step.matchAny.contains { selector in
                    selector.matches(events[index], catalog: catalog)
                }
            }
            return DiagnosticsExpectedStepRow(
                stepID: step.id,
                value: expectedValue(step),
                required: step.required,
                matchedEventID: matchedIndex.map { events[$0].eventID }
            )
        }
        let actual = events.map { event in
            let matchedSteps = flow.steps.filter { step in
                step.matchAny.contains { $0.matches(event, catalog: catalog) }
            }
            return DiagnosticsActualEventRow(
                id: event.eventID,
                value: actualValue(event),
                matchedStepIDs: matchedSteps.map(\.id)
            )
        }
        return .init(
            operationID: operationID,
            flowID: flow.id,
            state: .ready,
            expected: expected,
            actual: actual
        )
    }

    private static func unavailable(
        operationID: String,
        state: DiagnosticsExpectedActualState,
        events: [ObservabilityEventSnapshot] = []
    ) -> Self {
        .init(
            operationID: operationID,
            flowID: nil,
            state: state,
            expected: [],
            actual: events.map { .init(id: $0.eventID, value: actualValue($0), matchedStepIDs: []) }
        )
    }

    private static func expectedValue(_ step: ObservabilityCatalog.ExpectedFlowStep) -> String {
        let selectors = step.matchAny.map { selector in
            let action = selector.actionID.map { "action=\($0)" }
                ?? selector.actionGroup.map { "group=\($0)" }
                ?? "action=-"
            return [action, "component=\(selector.componentID)", selector.phase.map { "phase=\($0)" }]
                .compactMap { $0 }
                .joined(separator: " ")
        }
        return "\(step.id): \(selectors.joined(separator: " OR "))"
    }

    private static func actualValue(_ event: ObservabilityEventSnapshot) -> String {
        "\(event.actionID) · \(event.componentID) · \(event.phase) · \(event.outcome)"
    }
}

private extension ObservabilityCatalog.ExpectedFlowSelector {
    func matches(_ event: ObservabilityEventSnapshot, catalog: ObservabilityCatalog) -> Bool {
        let actionMatches = actionID.map { event.actionID == $0 }
            ?? actionGroup.map { catalog.group(forActionID: event.actionID) == $0 }
            ?? false
        return actionMatches
            && event.componentID == componentID
            && (phase == nil || event.phase == phase)
    }
}
