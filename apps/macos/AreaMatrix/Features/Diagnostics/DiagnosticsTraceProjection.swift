import Foundation

struct DiagnosticsSpanRow: Identifiable {
    var id: String {
        event.eventID
    }

    let event: ObservabilityEventSnapshot
    let depth: Int
    let isDetachedRoot: Bool
}

struct DiagnosticsCausalNode: Identifiable {
    let id: String
    let technicalID: String
    let actionID: String
    let componentID: String
}

struct DiagnosticsCausalEdge: Identifiable {
    enum Kind: String {
        case parentSpan
        case retry
    }

    var id: String {
        "\(kind.rawValue):\(sourceID):\(destinationID)"
    }

    let kind: Kind
    let sourceID: String
    let destinationID: String
}

struct DiagnosticsCausalProjection {
    let nodes: [DiagnosticsCausalNode]
    let edges: [DiagnosticsCausalEdge]

    static func make(events: [ObservabilityEventSnapshot]) -> Self {
        let sorted = events.sorted(by: DiagnosticsEventOrdering.areInIncreasingOrder)
        var nodes: [DiagnosticsCausalNode] = []
        var seenSpans = Set<String>()
        var edges: [DiagnosticsCausalEdge] = []
        var seenEdges = Set<String>()

        for event in sorted where seenSpans.insert(event.spanID).inserted {
            nodes.append(.init(
                id: "span:\(event.spanID)",
                technicalID: event.spanID,
                actionID: event.actionID,
                componentID: event.componentID
            ))
        }
        var seenOperations = Set<String>()
        for event in sorted {
            if let operation = event.operationID, seenOperations.insert(operation).inserted {
                nodes.append(.init(
                    id: "operation:\(operation)",
                    technicalID: operation,
                    actionID: event.actionID,
                    componentID: event.componentID
                ))
            }
            if let retry = event.retryOfOperationID, seenOperations.insert(retry).inserted {
                nodes.append(.init(
                    id: "operation:\(retry)",
                    technicalID: retry,
                    actionID: "-",
                    componentID: "-"
                ))
            }
        }
        for event in sorted {
            appendEdges(for: event, edges: &edges, seen: &seenEdges)
        }
        return .init(nodes: nodes, edges: edges)
    }

    private static func appendEdges(
        for event: ObservabilityEventSnapshot,
        edges: inout [DiagnosticsCausalEdge],
        seen: inout Set<String>
    ) {
        if let parent = event.parentSpanID, parent != event.spanID {
            append(.parentSpan, source: parent, destination: event.spanID, edges: &edges, seen: &seen)
        }
        if let retry = event.retryOfOperationID, let operation = event.operationID {
            append(.retry, source: retry, destination: operation, edges: &edges, seen: &seen)
        }
    }

    private static func append(
        _ kind: DiagnosticsCausalEdge.Kind,
        source: String,
        destination: String,
        edges: inout [DiagnosticsCausalEdge],
        seen: inout Set<String>
    ) {
        let edge = DiagnosticsCausalEdge(kind: kind, sourceID: source, destinationID: destination)
        if seen.insert(edge.id).inserted { edges.append(edge) }
    }
}

enum DiagnosticsSpanTreeProjection {
    private struct Accumulator {
        var visited = Set<String>()
        var rows: [DiagnosticsSpanRow] = []
    }

    static func rows(_ events: [ObservabilityEventSnapshot]) -> [DiagnosticsSpanRow] {
        let sorted = events.sorted(by: DiagnosticsEventOrdering.areInIncreasingOrder)
        let grouped = Dictionary(grouping: sorted, by: \.spanID)
        let order = spanOrder(sorted)
        let parents = parentMap(events: sorted)
        let children = childMap(parents: parents, order: order)
        let roots = grouped.keys.filter { span in
            parents[span].map { parent in grouped[parent] == nil } ?? true
        }
        .sorted { (order[$0] ?? 0) < (order[$1] ?? 0) }
        var accumulator = Accumulator()

        for root in roots {
            append(root: root, detached: parents[root] != nil, grouped: grouped,
                   children: children, accumulator: &accumulator)
        }
        for span in grouped.keys.sorted(by: { (order[$0] ?? 0) < (order[$1] ?? 0) })
            where !accumulator.visited.contains(span) {
            append(root: span, detached: true, grouped: grouped,
                   children: children, accumulator: &accumulator)
        }
        return accumulator.rows
    }

    private static func parentMap(events: [ObservabilityEventSnapshot]) -> [String: String] {
        var result: [String: String] = [:]
        for event in events {
            guard let parent = event.parentSpanID, parent != event.spanID, result[event.spanID] == nil else { continue }
            result[event.spanID] = parent
        }
        return result
    }

    private static func spanOrder(_ events: [ObservabilityEventSnapshot]) -> [String: Int] {
        var result: [String: Int] = [:]
        for (index, event) in events.enumerated() where result[event.spanID] == nil {
            result[event.spanID] = index
        }
        return result
    }

    private static func childMap(parents: [String: String], order: [String: Int]) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for (child, parent) in parents {
            result[parent, default: []].append(child)
        }
        for parent in result.keys {
            result[parent]?.sort { (order[$0] ?? 0) < (order[$1] ?? 0) }
        }
        return result
    }

    private static func append(
        root: String,
        detached: Bool,
        grouped: [String: [ObservabilityEventSnapshot]],
        children: [String: [String]],
        accumulator: inout Accumulator
    ) {
        var stack = [(root, 0, detached)]
        while let (span, depth, isDetached) = stack.popLast() {
            guard accumulator.visited.insert(span).inserted else { continue }
            for event in grouped[span] ?? [] {
                accumulator.rows.append(.init(event: event, depth: min(depth, 12), isDetachedRoot: isDetached))
            }
            for child in (children[span] ?? []).reversed() {
                stack.append((child, depth + 1, false))
            }
        }
    }
}

enum DiagnosticsEventOrdering {
    static func areInIncreasingOrder(
        _ lhs: ObservabilityEventSnapshot,
        _ rhs: ObservabilityEventSnapshot
    ) -> Bool {
        if lhs.sequenceNumber != rhs.sequenceNumber { return lhs.sequenceNumber < rhs.sequenceNumber }
        if lhs.monotonicTimestampNanoseconds != rhs.monotonicTimestampNanoseconds {
            return lhs.monotonicTimestampNanoseconds < rhs.monotonicTimestampNanoseconds
        }
        if lhs.wallTimestampMilliseconds != rhs.wallTimestampMilliseconds {
            return lhs.wallTimestampMilliseconds < rhs.wallTimestampMilliseconds
        }
        return lhs.eventID < rhs.eventID
    }
}
