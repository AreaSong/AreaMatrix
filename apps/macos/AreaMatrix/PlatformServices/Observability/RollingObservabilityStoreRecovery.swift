import Foundation

extension RollingObservabilityStore {
    func loadRecentEvents(limit: Int) throws -> [ObservabilityEventSnapshot] {
        let limit = max(0, min(limit, ObservabilityStoreRecordCodec.maximumRecoveredEvents))
        guard limit > 0 else { return [] }
        let state = try readableManifestState()
        let inventory = try fileIO.inventory()
        let files = state.matchingEntries(kind: .event, where: \.isReadable)
            .compactMap(inventory.file)
            .sorted(by: ObservabilityStorePolicy.eventFileOrder)
        var output: [ObservabilityEventSnapshot] = []
        for file in files.reversed() where output.count < limit {
            let data = try fileIO.read(
                file.url,
                maximumBytes: ObservabilityStorePolicy.rotationReadLimit(override: rotationBytesOverride)
            )
            output.insert(contentsOf: codec.decodeEvents(data).suffix(limit - output.count), at: 0)
        }
        return output
    }

    func loadRecoverableIncidents(
        currentSessionID: String,
        maximumEvents: Int = ObservabilityStoreRecordCodec.maximumRecoveredEvents
    ) throws -> [ObservabilityRecoveredIncident] {
        let state = try readableManifestState()
        let inventory = try fileIO.inventory()
        let entries = state.matchingEntries(kind: .incident, where: \.isReadable)
        let files = entries.compactMap { entry -> (ObservabilityStoreManifestEntry, ObservabilityOwnedFile)? in
            inventory.file(for: entry).map { (entry, $0) }
        }.sorted { ObservabilityStorePolicy.oldestFirst($0.1, $1.1) }.suffix(50)
        return files.compactMap { entry, file in
            guard let incidentID = fileIO.incidentID(for: file.url),
                  let committedBytes = entry.committedBytes,
                  committedBytes <= file.size,
                  let data = try? fileIO.readPrefix(file.url, byteCount: committedBytes),
                  let incident = codec.decodeIncident(
                      data,
                      expectedIncidentID: incidentID,
                      currentSessionID: currentSessionID,
                      nowMilliseconds: ObservabilityStorePolicy.milliseconds(now()),
                      maximumEvents: maximumEvents
                  )
            else { return nil }
            let disposition: ObservabilityIncidentLedger.PersistenceDisposition =
                entry.disposition == .managed ? .manifestOwned : .readOnly
            return ObservabilityRecoveredIncident(snapshot: incident, disposition: disposition)
        }
    }

    func loadIncidentSnapshots(
        currentSessionID: String,
        maximumEvents: Int = ObservabilityStoreRecordCodec.maximumRecoveredEvents
    ) throws -> [ObservabilityIncidentSnapshot] {
        try loadRecoverableIncidents(
            currentSessionID: currentSessionID,
            maximumEvents: maximumEvents
        ).map(\.snapshot)
    }
}
