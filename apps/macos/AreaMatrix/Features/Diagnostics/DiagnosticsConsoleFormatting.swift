import Foundation

enum DiagnosticsRawEncoder {
    static func encode(_ event: ObservabilityEventSnapshot) -> String {
        encode(event) { value in
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return try encoder.encode(value)
        }
    }

    static func encode(
        _ event: ObservabilityEventSnapshot,
        using encoder: (ObservabilityEventSnapshot) throws -> Data
    ) -> String {
        do {
            let data = try encoder(event)
            return String(data: data, encoding: .utf8) ?? fallback(eventID: event.eventID)
        } catch {
            return fallback(eventID: event.eventID)
        }
    }

    private static func fallback(eventID: String) -> String {
        struct Failure: Codable { let encodingError: Bool; let eventID: String }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(Failure(encodingError: true, eventID: eventID)) else {
            return "{\"encodingError\":true}"
        }
        return String(data: data, encoding: .utf8) ?? "{\"encodingError\":true}"
    }
}

enum DiagnosticsFingerprint {
    static func make(events: [ObservabilityEventSnapshot]) -> String {
        make(treeRows: DiagnosticsSpanTreeProjection.rows(events))
    }

    static func make(treeRows: [DiagnosticsSpanRow]) -> String {
        var ordinalBySpan: [String: Int] = [:]
        let stable = treeRows.enumerated().map { index, row in
            let event = row.event
            if ordinalBySpan[event.spanID] == nil { ordinalBySpan[event.spanID] = index }
            let parent = event.parentSpanID.flatMap { ordinalBySpan[$0] }.map { String($0) } ?? "-"
            return [event.actionID, event.componentID, event.phase, event.outcome,
                    event.error?.code ?? "-", String(row.depth), parent].joined(separator: "|")
        }.joined(separator: "\n")
        return String(format: "amx-%016llx", fnv1a64(stable.utf8))
    }

    private static func fnv1a64(_ bytes: String.UTF8View) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return hash
    }
}

struct DiagnosticsTraceDiffProjection {
    let onlyBaseline: [String]
    let shared: [String]
    let onlyComparison: [String]

    static func compare(
        baseline: [ObservabilityEventSnapshot],
        comparison: [ObservabilityEventSnapshot]
    ) -> Self {
        let lhs = occurrenceSignatures(baseline)
        let rhs = occurrenceSignatures(comparison)
        let lhsSet = Set(lhs)
        let rhsSet = Set(rhs)
        return .init(
            onlyBaseline: lhs.filter { !rhsSet.contains($0) },
            shared: lhs.filter(rhsSet.contains),
            onlyComparison: rhs.filter { !lhsSet.contains($0) }
        )
    }

    private static func occurrenceSignatures(_ events: [ObservabilityEventSnapshot]) -> [String] {
        var occurrences: [String: Int] = [:]
        return events.sorted(by: DiagnosticsEventOrdering.areInIncreasingOrder).map { event in
            let base = [event.actionID, event.componentID, event.phase, event.outcome,
                        event.error?.code ?? "-"].joined(separator: "|")
            occurrences[base, default: 0] += 1
            return "\(base)#\(occurrences[base, default: 0])"
        }
    }
}

enum DiagnosticsTerminalFormatter {
    static func line(_ event: ObservabilityEventSnapshot) -> String {
        let resources = event.resources.map(\.resourceID).joined(separator: ",")
        let fields = [
            "seq=\(event.sequenceNumber)", "mono_ns=\(event.monotonicTimestampNanoseconds)",
            "level=\(event.severity.rawValue)", "session=\(token(event.sessionID))",
            "incident=\(token(event.incidentID))", "trace=\(token(event.traceID))",
            "span=\(token(event.spanID))", "parent=\(token(event.parentSpanID))",
            "operation=\(token(event.operationID))", "retry=\(token(event.retryOfOperationID))",
            "action=\(token(event.actionID))", "component=\(token(event.componentID))",
            "phase=\(token(event.phase))", "outcome=\(token(event.outcome))",
            "duration_ms=\(event.durationMilliseconds.map { String($0) } ?? "-")",
            "resources=\(token(resources.isEmpty ? nil : resources))",
            "error=\(token(event.error?.code))"
        ]
        return fields.joined(separator: " ")
    }

    private static func token(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "-" }
        return value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: " ", with: "\\x20")
    }
}
