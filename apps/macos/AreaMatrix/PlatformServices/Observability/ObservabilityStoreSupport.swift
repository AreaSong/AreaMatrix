import Foundation

private struct ObservabilityIncidentPrefix {
    let records: [ObservabilityIncidentRecord]
    let byteCount: Int64
    let state: ObservabilityIncidentJournalState
}

struct ObservabilityStoreRecordCodec {
    static let maximumEventBytes = 256 * 1024
    static let maximumRecoveredEvents = 50000

    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    }

    func encodedEvent(_ event: ObservabilityEventSnapshot) throws -> Data {
        try validateCurrentEvent(event)
        return try lineData(event)
    }

    func encodedRecord(_ record: ObservabilityIncidentRecord) throws -> Data {
        if let event = record.event { try validateCurrentEvent(event) }
        if let incident = record.incident { try validateCurrentIncident(incident) }
        return try lineData(record)
    }

    func validateCurrentEvent(_ event: ObservabilityEventSnapshot) throws {
        guard event.schemaVersion == 2 else { throw ObservabilityStoreError.unsupportedSchema }
    }

    func validateCurrentIncident(_ incident: ObservabilityIncidentSnapshot) throws {
        guard incident.events.allSatisfy({ $0.schemaVersion == 2 }) else {
            throw ObservabilityStoreError.unsupportedSchema
        }
    }

    func decodeEvents(_ data: Data) -> [ObservabilityEventSnapshot] {
        var events: [ObservabilityEventSnapshot] = []
        for line in completeLines(data) {
            guard !line.data.isEmpty,
                  line.data.count <= Self.maximumEventBytes,
                  let event = try? decoder.decode(ObservabilityEventSnapshot.self, from: line.data)
            else { break }
            events.append(event)
        }
        return events
    }

    func decodeIncident(
        _ data: Data,
        expectedIncidentID: String,
        currentSessionID: String,
        nowMilliseconds: Int64,
        maximumEvents: Int = ObservabilityStoreRecordCodec.maximumRecoveredEvents
    ) -> ObservabilityIncidentSnapshot? {
        guard let parsed = incidentPrefix(data, expectedIncidentID: expectedIncidentID) else { return nil }
        return ObservabilityIncidentSnapshot.recovered(
            from: parsed.records,
            currentSessionID: currentSessionID,
            nowMilliseconds: nowMilliseconds,
            maximumEvents: max(0, min(maximumEvents, Self.maximumRecoveredEvents))
        )
    }

    func validIncidentPrefixLength(_ data: Data, expectedIncidentID: String) -> Int64? {
        incidentPrefix(data, expectedIncidentID: expectedIncidentID)?.byteCount
    }

    func incidentJournalState(
        _ data: Data,
        expectedIncidentID: String
    ) -> ObservabilityIncidentJournalState? {
        incidentPrefix(data, expectedIncidentID: expectedIncidentID)?.state
    }

    func nextIncidentJournalState(
        appending record: ObservabilityIncidentRecord,
        to currentState: ObservabilityIncidentJournalState
    ) throws -> ObservabilityIncidentJournalState {
        var state = currentState
        guard valid(record, expectedIncidentID: record.incidentID, state: &state) else {
            throw ObservabilityStoreError.readOnly
        }
        return state
    }

    private func lineData(_ value: some Encodable) throws -> Data {
        var data = try encoder.encode(value)
        guard data.count <= Self.maximumEventBytes else { throw ObservabilityStoreError.eventTooLarge }
        data.append(0x0A)
        return data
    }

    private func incidentPrefix(
        _ data: Data,
        expectedIncidentID: String
    ) -> ObservabilityIncidentPrefix? {
        var records: [ObservabilityIncidentRecord] = []
        var state = ObservabilityIncidentJournalState.expectingHeader
        var byteCount: Int64 = 0
        for line in completeLines(data) {
            guard !line.data.isEmpty,
                  line.data.count <= Self.maximumEventBytes,
                  let record = try? decoder.decode(ObservabilityIncidentRecord.self, from: line.data),
                  valid(record, expectedIncidentID: expectedIncidentID, state: &state)
            else { break }
            records.append(record)
            byteCount = line.endOffset
        }
        guard !records.isEmpty else { return nil }
        return ObservabilityIncidentPrefix(records: records, byteCount: byteCount, state: state)
    }

    private func valid(
        _ record: ObservabilityIncidentRecord,
        expectedIncidentID: String,
        state: inout ObservabilityIncidentJournalState
    ) -> Bool {
        guard record.incidentID == expectedIncidentID else { return false }
        switch record.kind {
        case .header:
            return validateHeader(record, expectedIncidentID: expectedIncidentID, state: &state)
        case .event:
            return validateEvent(record, expectedIncidentID: expectedIncidentID, state: state)
        case .freeze:
            return validateFreeze(record, state: &state)
        case .status:
            return validateStatus(record, state: &state)
        }
    }

    private func validateHeader(
        _ record: ObservabilityIncidentRecord,
        expectedIncidentID: String,
        state: inout ObservabilityIncidentJournalState
    ) -> Bool {
        guard state == .expectingHeader,
              let incident = record.incident,
              incident.id == expectedIncidentID,
              incident.events.isEmpty,
              record.event == nil,
              record.status == nil,
              record.frozenAtMilliseconds == nil
        else { return false }
        state = .capturing
        return true
    }

    private func validateEvent(
        _ record: ObservabilityIncidentRecord,
        expectedIncidentID: String,
        state: ObservabilityIncidentJournalState
    ) -> Bool {
        state == .capturing
            && record.incident == nil
            && record.event?.incidentID == expectedIncidentID
            && record.status == nil
            && record.frozenAtMilliseconds == nil
    }

    private func validateFreeze(
        _ record: ObservabilityIncidentRecord,
        state: inout ObservabilityIncidentJournalState
    ) -> Bool {
        guard state == .capturing,
              record.incident == nil,
              record.event == nil,
              record.status == nil,
              record.frozenAtMilliseconds != nil
        else { return false }
        state = .frozen
        return true
    }

    private func validateStatus(
        _ record: ObservabilityIncidentRecord,
        state: inout ObservabilityIncidentJournalState
    ) -> Bool {
        guard state != .expectingHeader,
              record.incident == nil,
              record.event == nil,
              let status = record.status
        else { return false }
        if state == .frozen {
            return status == .open ? record.frozenAtMilliseconds == nil : true
        }
        guard record.frozenAtMilliseconds != nil else { return status == .open }
        guard status != .open else { return false }
        state = .frozen
        return true
    }

    private func completeLines(_ data: Data) -> [CompleteJSONLine] {
        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: false)
        guard lines.count > 1 else { return [] }
        var output: [CompleteJSONLine] = []
        var endOffset: Int64 = 0
        for line in lines.dropLast() {
            guard let lineBytes = Int64(exactly: line.count) else { break }
            let (lineEnd, lineOverflow) = endOffset.addingReportingOverflow(lineBytes)
            let (nextOffset, newlineOverflow) = lineEnd.addingReportingOverflow(1)
            guard !lineOverflow, !newlineOverflow else { break }
            endOffset = nextOffset
            output.append(CompleteJSONLine(data: Data(line), endOffset: endOffset))
        }
        return output
    }
}

enum ObservabilityIncidentJournalState {
    case expectingHeader
    case capturing
    case frozen
}

private struct CompleteJSONLine {
    let data: Data
    let endOffset: Int64
}

enum ObservabilityStorePolicy {
    static func eventFileOrder(_ lhs: ObservabilityOwnedFile, _ rhs: ObservabilityOwnedFile) -> Bool {
        let left = ObservabilityStoreManifestState.sequence(fromEventFileName: lhs.url.lastPathComponent)
        let right = ObservabilityStoreManifestState.sequence(fromEventFileName: rhs.url.lastPathComponent)
        if let left, let right { return left < right }
        return oldestFirst(lhs, rhs)
    }

    static func oldestFirst(_ lhs: ObservabilityOwnedFile, _ rhs: ObservabilityOwnedFile) -> Bool {
        if lhs.modifiedAt == rhs.modifiedAt { return lhs.url.lastPathComponent < rhs.url.lastPathComponent }
        return lhs.modifiedAt < rhs.modifiedAt
    }

    static func isProtected(_ url: URL, by protectedURLs: Set<URL>) -> Bool {
        let path = url.standardizedFileURL.path
        return protectedURLs.contains { $0.standardizedFileURL.path == path }
    }

    static func rotationLimit(
        configuration: AppObservabilityConfiguration,
        override: Int64?
    ) -> Int64 {
        if let override { return max(1, override) }
        return min(5 * 1024 * 1024, max(1 * 1024 * 1024, configuration.diskBudgetBytes / 4))
    }

    static func rotationReadLimit(override: Int64?) -> Int64 {
        let base = max(5 * 1024 * 1024, override ?? 0)
        let (limit, overflow) = base.addingReportingOverflow(
            Int64(ObservabilityStoreRecordCodec.maximumEventBytes)
        )
        return overflow ? .max : limit
    }

    static func milliseconds(_ date: Date) -> Int64 {
        ObservabilityTime.milliseconds(date)
    }

    static func defaultRootURL(fileManager: FileManager) -> URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AreaMatrix", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
    }
}

enum ObservabilityStoreArithmetic {
    static func bytes(_ count: Int) throws -> Int64 {
        guard let value = Int64(exactly: count), value >= 0 else {
            throw ObservabilityStoreError.fileTooLarge
        }
        return value
    }

    static func adding(_ lhs: Int64, _ rhs: Int64) throws -> Int64 {
        guard lhs >= 0, rhs >= 0 else { throw ObservabilityStoreError.fileTooLarge }
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow, value >= 0 else { throw ObservabilityStoreError.fileTooLarge }
        return value
    }

    static func subtracting(_ lhs: Int64, _ rhs: Int64) throws -> Int64 {
        guard lhs >= 0, rhs >= 0, rhs <= lhs else {
            throw ObservabilityStoreError.fileTooLarge
        }
        return lhs - rhs
    }

    static func sum(_ values: some Sequence<Int64>) throws -> Int64 {
        try values.reduce(Int64(0), adding)
    }

    static func retentionInterval(hours: Int) -> TimeInterval {
        guard hours > 0, let hours = Int64(exactly: hours) else { return 0 }
        let (seconds, overflow) = hours.multipliedReportingOverflow(by: 3600)
        return TimeInterval(overflow ? Int64.max : seconds)
    }
}

enum ObservabilityTime {
    static func milliseconds(_ date: Date) -> Int64 {
        let value = date.timeIntervalSince1970 * 1000
        guard !value.isNaN else { return 0 }
        if value >= Double(Int64.max) { return .max }
        if value <= Double(Int64.min) { return .min }
        return Int64(value)
    }
}

extension RollingObservabilityStore {
    func encodedIncident(_ incident: ObservabilityIncidentSnapshot) throws -> Data {
        var data = try codec.encodedRecord(.header(incident))
        guard data.count <= Self.maximumIncidentBytes else {
            throw ObservabilityStoreError.incidentTooLarge
        }
        for event in incident.events {
            let record = try codec.encodedRecord(.event(incident.id, event))
            let next = try ObservabilityStoreArithmetic.adding(
                ObservabilityStoreArithmetic.bytes(data.count),
                ObservabilityStoreArithmetic.bytes(record.count)
            )
            guard next <= Self.maximumIncidentBytes else {
                throw ObservabilityStoreError.incidentTooLarge
            }
            data.append(record)
        }
        if incident.isFrozen || incident.status != .open {
            let freeze = try codec.encodedRecord(.freeze(
                incident.id,
                incident.captureEndsAtMilliseconds
            ))
            let next = try ObservabilityStoreArithmetic.adding(
                ObservabilityStoreArithmetic.bytes(data.count),
                ObservabilityStoreArithmetic.bytes(freeze.count)
            )
            guard next <= Self.maximumIncidentBytes else {
                throw ObservabilityStoreError.incidentTooLarge
            }
            data.append(freeze)
        }
        return data
    }

    mutating func createManagedIncident(_ data: Data, id: String) throws {
        var name = ""
        try refreshPhysicalOccupancy()
        try persistManifestMutation { state in
            name = try state.reserveIncident(id: id)
        }.requireDurable()
        do {
            try fileIO.writeIncidentExclusive(data, id: id, synchronize: true)
            let result = try persistManifestMutation {
                try $0.markManaged(
                    name,
                    committedBytes: ObservabilityStoreArithmetic.bytes(data.count)
                )
            }
            try result.requireDurable()
            guard let state = codec.incidentJournalState(data, expectedIncidentID: id) else {
                throw ObservabilityStoreError.unsafePath
            }
            incidentJournalStates[id] = state
        } catch {
            abandonCreation(named: name)
            throw error
        }
    }
}
