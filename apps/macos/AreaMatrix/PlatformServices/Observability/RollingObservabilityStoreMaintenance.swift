import Foundation

extension RollingObservabilityStore {
    mutating func enforceRetention(
        configuration: AppObservabilityConfiguration,
        requiredBytes: Int64 = 0,
        protectedURLs: Set<URL> = []
    ) throws {
        let cutoff = now().addingTimeInterval(
            -ObservabilityStoreArithmetic.retentionInterval(hours: configuration.retentionHours)
        )
        try refreshUsage()
        let expired = try managedFiles().filter {
            $0.file.modifiedAt < cutoff
                && !ObservabilityStorePolicy.isProtected($0.file.url, by: protectedURLs)
        }.sorted { ObservabilityStorePolicy.oldestFirst($0.file, $1.file) }
        for candidate in expired {
            try removeForRetention(candidate.entry)
        }
        while try projectedUsage(requiredBytes) > configuration.diskBudgetBytes {
            guard let candidate = try oldestUnprotectedManagedFile(protectedURLs) else { break }
            try removeForRetention(candidate.entry)
        }
        guard try projectedUsage(requiredBytes) <= configuration.diskBudgetBytes else {
            throw ObservabilityStoreError.budgetExceeded
        }
    }

    mutating func resumePendingDeletions() throws {
        let names = manifest.entries.values
            .filter { $0.disposition == .pendingDeletion }
            .map(\.name)
            .sorted()
        for name in names {
            if let id = incidentID(forManifestName: name) {
                readOnlyIncidentIDs.insert(id)
            }
            try removePendingFile(named: name)
        }
    }

    mutating func beginDeletion(
        _ names: Set<String>,
        reportsIncidentRevocation: Bool
    ) throws {
        guard !names.isEmpty else { return }
        let incidentIDs = reportsIncidentRevocation
            ? Set(names.compactMap(incidentID(forManifestName:)))
            : []
        let result = try persistManifestMutation { try $0.markPendingDeletion(names) }
        readOnlyIncidentIDs.formUnion(incidentIDs)
        for id in incidentIDs {
            incidentJournalStates.removeValue(forKey: id)
        }
        try result.requireDurable()
    }

    mutating func removePendingFile(named name: String) throws {
        guard let entry = manifest.entry(named: name), entry.disposition == .pendingDeletion else {
            throw ObservabilityStoreError.unsafePath
        }
        do {
            try fileIO.removeOwnedFile(at: fileIO.url(for: entry))
        } catch ObservabilitySafeFileError.missing {
            // Persisted pending deletion already removed all read authority.
        }
        try persistManifestMutation { $0.completeDeletion(name) }.requireDurable()
    }

    mutating func abandonCreation(named name: String) {
        guard !name.isEmpty, manifest.entry(named: name) != nil else { return }
        do {
            let remainsOccupied = try fileIO.inventory().occupiedNames.contains(name)
            try persistManifestMutation {
                try $0.cancelCreation(name, remainsOccupied: remainsOccupied)
            }.requireDurable()
        } catch {
            return
        }
    }

    mutating func markIncidentReadOnly(id: String) throws {
        let name = "incident-\(id).jsonl"
        readOnlyIncidentIDs.insert(id)
        incidentJournalStates.removeValue(forKey: id)
        let result = try persistManifestMutation { try $0.markReadOnly(name) }
        try result.requireDurable()
    }

    mutating func persistManifestMutation(
        _ mutation: (inout ObservabilityStoreManifestState) throws -> Void
    ) throws -> ObservabilityStoreManifestPersistResult {
        guard !manifestReloadRequired else { throw ObservabilityStoreError.unavailable }
        var candidate = manifest
        try mutation(&candidate)
        let result = try manifestOperations.persist(fileIO, candidate.snapshot())
        manifest = candidate
        if result == .replacedDurabilityUncertain {
            manifestReloadRequired = true
        }
        return result
    }

    mutating func persistManifest() throws -> ObservabilityStoreManifestPersistResult {
        let result = try manifestOperations.persist(fileIO, manifest.snapshot())
        if result == .replacedDurabilityUncertain {
            manifestReloadRequired = true
        }
        return result
    }

    func readableManifestState() throws -> ObservabilityStoreManifestState {
        try ObservabilityStoreManifestState.recover(using: fileIO).state
    }

    mutating func reloadManifestAuthority() throws {
        let recovery = try ObservabilityStoreManifestState.recover(using: fileIO)
        let requiresPersistence = recovery.requiresPersistence || manifestReloadRequired
        manifest = recovery.state
        if requiresPersistence {
            try persistManifest().requireDurable()
        }
        manifestReloadRequired = false
        try reconcileIncidentJournalTails()
        try resumePendingDeletions()
        try rebuildIncidentJournalStates()
        let readOnlyIDs = manifest.entries.values.compactMap { entry -> String? in
            guard entry.kind == .incident, entry.disposition == .readOnly else { return nil }
            return incidentID(forManifestName: entry.name)
        }
        readOnlyIncidentIDs.formUnion(readOnlyIDs)
    }

    mutating func refreshPhysicalOccupancy() throws {
        let inventory = try fileIO.inventory()
        manifest.refreshOccupiedNames(inventory.occupiedNames)
    }

    mutating func refreshUsage() throws {
        let inventory = try fileIO.inventory()
        usageBytes = try ObservabilityStoreArithmetic.sum(inventory.files.map(\.size))
        let managedSizes = manifest.entries.values.compactMap { entry -> Int64? in
            guard entry.disposition == .managed else { return nil }
            return inventory.file(for: entry)?.size
        }
        managedUsageBytes = try ObservabilityStoreArithmetic.sum(managedSizes)
    }

    mutating func reconcileIncidentJournalTails() throws {
        let inventory = try fileIO.inventory()
        let entries = manifest.matchingEntries(kind: .incident) { $0 == .managed }
        for entry in entries.sorted(by: { $0.name < $1.name }) {
            guard let committedBytes = entry.committedBytes,
                  let file = inventory.file(for: entry),
                  file.size > committedBytes,
                  let id = incidentID(forManifestName: entry.name)
            else { continue }
            do {
                try fileIO.truncateIncident(id: id, to: committedBytes)
            } catch {
                try markIncidentReadOnly(id: id)
                throw error
            }
        }
    }

    mutating func rebuildIncidentJournalStates() throws {
        let inventory = try fileIO.inventory()
        var rebuilt: [String: ObservabilityIncidentJournalState] = [:]
        let entries = manifest.matchingEntries(kind: .incident) { $0 == .managed }
        for entry in entries {
            guard let committedBytes = entry.committedBytes,
                  let file = inventory.file(for: entry),
                  let id = incidentID(forManifestName: entry.name)
            else { throw ObservabilityStoreError.corruptManifest }
            let data = try fileIO.readPrefix(file.url, byteCount: committedBytes)
            guard let state = codec.incidentJournalState(data, expectedIncidentID: id) else {
                throw ObservabilityStoreError.corruptManifest
            }
            rebuilt[id] = state
        }
        incidentJournalStates = rebuilt
    }
}

private extension RollingObservabilityStore {
    func projectedUsage(_ additionalBytes: Int64) throws -> Int64 {
        try ObservabilityStoreArithmetic.adding(usageBytes, additionalBytes)
    }

    func managedFiles() throws -> [(entry: ObservabilityStoreManifestEntry, file: ObservabilityOwnedFile)] {
        let inventory = try fileIO.inventory()
        return manifest.entries.values.compactMap { entry in
            guard entry.disposition == .managed, let file = inventory.file(for: entry) else { return nil }
            return (entry, file)
        }
    }

    func oldestUnprotectedManagedFile(
        _ protectedURLs: Set<URL>
    ) throws -> (entry: ObservabilityStoreManifestEntry, file: ObservabilityOwnedFile)? {
        try managedFiles()
            .filter { !ObservabilityStorePolicy.isProtected($0.file.url, by: protectedURLs) }
            .min { ObservabilityStorePolicy.oldestFirst($0.file, $1.file) }
    }

    mutating func removeForRetention(_ entry: ObservabilityStoreManifestEntry) throws {
        try beginDeletion([entry.name], reportsIncidentRevocation: true)
        try removePendingFile(named: entry.name)
        try refreshUsage()
    }

    func incidentID(forManifestName name: String) -> String? {
        guard let entry = manifest.entry(named: name), entry.kind == .incident else { return nil }
        return fileIO.incidentID(for: URL(fileURLWithPath: entry.name))
    }
}
