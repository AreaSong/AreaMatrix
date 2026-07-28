import Foundation

enum DiagnosticsDurationFilter: String, CaseIterable, Hashable {
    case underTen
    case tenToHundred
    case hundredToThousand
    case overThousand
    case unknown

    func contains(_ duration: UInt64?) -> Bool {
        switch (self, duration) {
        case (.unknown, nil): true
        case let (.underTen, value?): value < 10
        case let (.tenToHundred, value?): (10 ..< 100).contains(value)
        case let (.hundredToThousand, value?): (100 ..< 1000).contains(value)
        case let (.overThousand, value?): value >= 1000
        default: false
        }
    }
}

struct DiagnosticsFilterState: Equatable {
    var searchText = ""
    var sessionID: String?
    var incidentID: String?
    var traceID: String?
    var operationID: String?
    var actionID: String?
    var componentID: String?
    var severity: AppObservabilitySeverity?
    var outcome: String?
    var duration: DiagnosticsDurationFilter?

    var isActive: Bool {
        !searchText.isEmpty || sessionID != nil || incidentID != nil || traceID != nil
            || operationID != nil || actionID != nil || componentID != nil
            || severity != nil || outcome != nil || duration != nil
    }

    mutating func clear() {
        self = .init()
    }
}

struct DiagnosticsFilterOptions {
    let sessionIDs: [String]
    let incidentIDs: [String]
    let traceIDs: [String]
    let operationIDs: [String]
    let actionIDs: [String]
    let componentIDs: [String]
    let severities: [AppObservabilitySeverity]
    let outcomes: [String]
}

struct DiagnosticsProjectedEvent: Identifiable {
    var id: String {
        event.eventID
    }

    let event: ObservabilityEventSnapshot
    let actionGroup: String?
    let terminalLine: String
    let rawJSON: String
    fileprivate let searchIndex: String
}

struct DiagnosticsTraceData {
    let events: [DiagnosticsProjectedEvent]
    let treeRows: [DiagnosticsSpanRow]
    let causal: DiagnosticsCausalProjection
    let fingerprint: String
    let revision: Int
    let operationIDs: [String]
    let operations: [String: DiagnosticsOperationData]
}

struct DiagnosticsOperationData: Identifiable {
    let id: String
    let events: [DiagnosticsProjectedEvent]
    let treeRows: [DiagnosticsSpanRow]
    let causal: DiagnosticsCausalProjection
    let expectedActual: DiagnosticsExpectedActualProjection
    let fingerprint: String
}

struct DiagnosticsFilteredProjection {
    let events: [DiagnosticsProjectedEvent]
    let traceIDs: [String]
    let traces: [String: DiagnosticsTraceData]
    let traceRevisionToken: [Int]

    static let empty = Self(events: [], traceIDs: [], traces: [:], traceRevisionToken: [])
}

struct DiagnosticsConsoleProjection {
    let events: [DiagnosticsProjectedEvent]
    let options: DiagnosticsFilterOptions
    private let catalog: ObservabilityCatalog?
    private let flowEvaluationContext: DiagnosticsFlowEvaluationContext

    var catalogSnapshot: ObservabilityCatalog? {
        catalog
    }

    init(
        events: [ObservabilityEventSnapshot],
        catalog: ObservabilityCatalog? = nil,
        flowEvaluationContext: DiagnosticsFlowEvaluationContext = .current
    ) {
        let sorted = events.sorted(by: DiagnosticsEventOrdering.areInIncreasingOrder)
        self.events = sorted.map { DiagnosticsProjectedEvent.make($0, catalog: catalog) }
        options = DiagnosticsFilterOptions(events: sorted)
        self.catalog = catalog
        self.flowEvaluationContext = flowEvaluationContext
    }

    func filtered(using filters: DiagnosticsFilterState) -> DiagnosticsFilteredProjection {
        let matching = events.filter { $0.matches(filters) }
        let visibleByTrace = Dictionary(grouping: matching, by: { $0.event.traceID })
        let allByTrace = Dictionary(grouping: events, by: { $0.event.traceID })
        let allByOperation = operationGroups(events)
        let traces = visibleByTrace.mapValues { visibleEntries in
            traceData(
                visibleEntries: visibleEntries,
                allByTrace: allByTrace,
                allByOperation: allByOperation
            )
        }
        let traceIDs = visibleByTrace.keys.sorted {
            guard let lhs = visibleByTrace[$0]?.last?.event,
                  let rhs = visibleByTrace[$1]?.last?.event
            else { return $0 < $1 }
            return DiagnosticsEventOrdering.areInIncreasingOrder(rhs, lhs)
        }
        return .init(
            events: matching,
            traceIDs: traceIDs,
            traces: traces,
            traceRevisionToken: traceIDs.compactMap { traces[$0]?.revision }
        )
    }

    private func traceData(
        visibleEntries: [DiagnosticsProjectedEvent],
        allByTrace: [String: [DiagnosticsProjectedEvent]],
        allByOperation: [String: [DiagnosticsProjectedEvent]]
    ) -> DiagnosticsTraceData {
        let traceID = visibleEntries[0].event.traceID
        let entries = allByTrace[traceID] ?? visibleEntries
        let snapshots = entries.map(\.event)
        let rows = DiagnosticsSpanTreeProjection.rows(snapshots)
        let allOperationIDs = Self.orderedOperationIDs(snapshots)
        let visibleOperationIDs = Self.orderedOperationIDs(visibleEntries.map(\.event))
        let operationIDs = visibleOperationIDs.isEmpty ? allOperationIDs : visibleOperationIDs
        return DiagnosticsTraceData(
            events: entries,
            treeRows: rows,
            causal: .make(events: snapshots),
            fingerprint: DiagnosticsFingerprint.make(treeRows: rows),
            revision: Self.traceRevision(snapshots),
            operationIDs: operationIDs,
            operations: Dictionary(uniqueKeysWithValues: operationIDs.map { operationID in
                (operationID, operationData(id: operationID, traceEntries: entries, allByOperation: allByOperation))
            })
        )
    }

    private func operationData(
        id: String,
        traceEntries: [DiagnosticsProjectedEvent],
        allByOperation: [String: [DiagnosticsProjectedEvent]]
    ) -> DiagnosticsOperationData {
        let operationEvents = allByOperation[id] ?? traceEntries.filter { $0.event.operationID == id }
        let snapshots = operationEvents.map(\.event)
        let rows = DiagnosticsSpanTreeProjection.rows(snapshots)
        return DiagnosticsOperationData(
            id: id,
            events: operationEvents,
            treeRows: rows,
            causal: .make(events: snapshots),
            expectedActual: .make(
                operationID: id,
                events: snapshots,
                catalog: catalog,
                evaluationContext: flowEvaluationContext
            ),
            fingerprint: DiagnosticsFingerprint.make(treeRows: rows)
        )
    }

    private func operationGroups(
        _ entries: [DiagnosticsProjectedEvent]
    ) -> [String: [DiagnosticsProjectedEvent]] {
        Dictionary(grouping: entries.compactMap { projected in
            projected.event.operationID == nil ? nil : projected
        }, by: { $0.event.operationID ?? "" })
    }

    private static func traceRevision(_ events: [ObservabilityEventSnapshot]) -> Int {
        var hasher = Hasher()
        for event in events {
            hasher.combine(event.eventID)
            hasher.combine(event.sequenceNumber)
            hasher.combine(event.monotonicTimestampNanoseconds)
            hasher.combine(event.actionID)
            hasher.combine(event.componentID)
            hasher.combine(event.phase)
            hasher.combine(event.outcome)
            hasher.combine(event.error?.code)
        }
        return hasher.finalize()
    }

    private static func orderedOperationIDs(_ events: [ObservabilityEventSnapshot]) -> [String] {
        var seen = Set<String>()
        return events.compactMap { event in
            guard let operationID = event.operationID, seen.insert(operationID).inserted else { return nil }
            return operationID
        }
    }
}

private extension DiagnosticsProjectedEvent {
    static func make(_ event: ObservabilityEventSnapshot, catalog: ObservabilityCatalog?) -> Self {
        let searchable = [event.sessionID, event.incidentID, event.traceID, event.operationID,
                          event.actionID, event.componentID, event.error?.code]
            .compactMap { $0 }.joined(separator: " ").lowercased()
        return .init(
            event: event,
            actionGroup: catalog?.group(forActionID: event.actionID),
            terminalLine: DiagnosticsTerminalFormatter.line(event),
            rawJSON: DiagnosticsRawEncoder.encode(event),
            searchIndex: searchable
        )
    }

    func matches(_ filter: DiagnosticsFilterState) -> Bool {
        let query = filter.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return (query.isEmpty || searchIndex.contains(query))
            && (filter.sessionID == nil || event.sessionID == filter.sessionID)
            && (filter.incidentID == nil || event.incidentID == filter.incidentID)
            && (filter.traceID == nil || event.traceID == filter.traceID)
            && (filter.operationID == nil || event.operationID == filter.operationID)
            && (filter.actionID == nil || event.actionID == filter.actionID)
            && (filter.componentID == nil || event.componentID == filter.componentID)
            && (filter.severity == nil || event.severity == filter.severity)
            && (filter.outcome == nil || event.outcome == filter.outcome)
            && (filter.duration?.contains(event.durationMilliseconds) ?? true)
    }
}

private extension DiagnosticsFilterOptions {
    init(events: [ObservabilityEventSnapshot]) {
        sessionIDs = Self.values(events.map(\.sessionID))
        incidentIDs = Self.values(events.compactMap(\.incidentID))
        traceIDs = Self.values(events.map(\.traceID))
        operationIDs = Self.values(events.compactMap(\.operationID))
        actionIDs = Self.values(events.map(\.actionID))
        componentIDs = Self.values(events.map(\.componentID))
        severities = AppObservabilitySeverity.allCases.filter { severity in
            events.contains { $0.severity == severity }
        }
        outcomes = Self.values(events.map(\.outcome))
    }

    static func values(_ values: [String]) -> [String] {
        Array(Set(values)).sorted()
    }
}
