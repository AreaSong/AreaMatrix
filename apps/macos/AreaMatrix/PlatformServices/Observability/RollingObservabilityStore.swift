import Foundation

struct ObservabilityRecoveredIncident {
    let snapshot: ObservabilityIncidentSnapshot
    let disposition: ObservabilityIncidentLedger.PersistenceDisposition
}

struct ObservabilityIncidentPersistenceChanges {
    var readOnlyIDs = Set<String>()
}

struct RollingObservabilityStore {
    static let maximumIncidentBytes: Int64 = 64 * 1024 * 1024

    private let rootURL: URL?
    let now: () -> Date
    let rotationBytesOverride: Int64?
    let codec = ObservabilityStoreRecordCodec()
    let fileIO: ObservabilityStoreFileIO
    private let durabilityOperations: ObservabilityStoreDurabilityOperations
    let manifestOperations: ObservabilityStoreManifestOperations
    var manifest = ObservabilityStoreManifestState(nextEventSequence: 0)
    private var handle: FileHandle?
    private var currentURL: URL?
    private var currentSize: Int64 = 0
    private var failureLatched = false
    private var shutdownLatched = false
    var manifestReloadRequired = false
    var readOnlyIncidentIDs = Set<String>()
    var incidentJournalStates: [String: ObservabilityIncidentJournalState] = [:]
    var usageBytes: Int64 = 0
    var managedUsageBytes: Int64 = 0
    private(set) var available = false
    private(set) var lastRotationAtMilliseconds: Int64?

    var storageRootURL: URL? {
        rootURL
    }

    init(
        fileManager: FileManager = .default,
        rootURL: URL? = nil,
        now: @escaping () -> Date = Date.init,
        rotationBytesOverride: Int64? = nil,
        durabilityOperations: ObservabilityStoreDurabilityOperations = .live,
        manifestOperations: ObservabilityStoreManifestOperations = .live
    ) {
        let resolvedRootURL = rootURL ?? ObservabilityStorePolicy.defaultRootURL(fileManager: fileManager)
        self.rootURL = resolvedRootURL
        self.now = now
        self.rotationBytesOverride = rotationBytesOverride
        self.durabilityOperations = durabilityOperations
        self.manifestOperations = manifestOperations
        fileIO = ObservabilityStoreFileIO(fileManager: fileManager, rootURL: resolvedRootURL)
    }

    mutating func prepare(
        configuration: AppObservabilityConfiguration,
        protectedURLs: Set<URL> = []
    ) throws {
        guard !shutdownLatched else { throw ObservabilityStoreError.unavailable }
        guard configuration.mode.persistsToDisk else {
            close()
            manifest = ObservabilityStoreManifestState(nextEventSequence: 0)
            manifestReloadRequired = false
            incidentJournalStates.removeAll(keepingCapacity: true)
            failureLatched = false
            return
        }
        do {
            close()
            try fileIO.prepareDirectories()
            try reloadManifestAuthority()
            try refreshUsage()
            try enforceRetention(configuration: configuration, protectedURLs: protectedURLs)
            try openNewFile()
            failureLatched = false
            available = true
        } catch {
            latchFailure()
            throw error
        }
    }

    mutating func append(
        _ event: ObservabilityEventSnapshot,
        configuration: AppObservabilityConfiguration
    ) throws {
        guard configuration.mode.persistsToDisk else { return }
        guard !failureLatched, !shutdownLatched else { throw ObservabilityStoreError.unavailable }
        try codec.validateCurrentEvent(event)
        do {
            try ensurePrepared(configuration: configuration)
            let data = try codec.encodedEvent(event)
            let bytes = try ObservabilityStoreArithmetic.bytes(data.count)
            try makeRoom(for: bytes, configuration: configuration, protectedURLs: protectedCurrentFile)
            try rotateIfNeeded(adding: bytes, configuration: configuration)
            guard let handle else { throw ObservabilityStoreError.unavailable }
            let nextCurrentSize = try ObservabilityStoreArithmetic.adding(currentSize, bytes)
            let nextUsage = try ObservabilityStoreArithmetic.adding(usageBytes, bytes)
            let nextManagedUsage = try ObservabilityStoreArithmetic.adding(managedUsageBytes, bytes)
            try handle.write(contentsOf: data)
            currentSize = nextCurrentSize
            usageBytes = nextUsage
            managedUsageBytes = nextManagedUsage
        } catch {
            refreshUsageAfterFailure()
            latchFailure()
            throw error
        }
    }

    mutating func beginIncident(
        _ incident: ObservabilityIncidentSnapshot,
        configuration: AppObservabilityConfiguration
    ) throws {
        guard configuration.mode.persistsToDisk else { return }
        guard !failureLatched, !shutdownLatched else { throw ObservabilityStoreError.unavailable }
        try codec.validateCurrentIncident(incident)
        do {
            try ensurePrepared(configuration: configuration)
            let data = try encodedIncident(incident)
            let bytes = try ObservabilityStoreArithmetic.bytes(data.count)
            let url = try fileIO.incidentURL(id: incident.id)
            try makeRoom(
                for: bytes,
                configuration: configuration,
                protectedURLs: protectedCurrentFile.union([url])
            )
            let nextUsage = try ObservabilityStoreArithmetic.adding(usageBytes, bytes)
            let nextManagedUsage = try ObservabilityStoreArithmetic.adding(managedUsageBytes, bytes)
            try createManagedIncident(data, id: incident.id)
            usageBytes = nextUsage
            managedUsageBytes = nextManagedUsage
            available = !failureLatched
        } catch {
            refreshUsageAfterFailure()
            latchFailure()
            throw error
        }
    }

    mutating func appendIncidentEvent(
        _ event: ObservabilityEventSnapshot,
        incidentID: String,
        configuration: AppObservabilityConfiguration
    ) throws {
        try codec.validateCurrentEvent(event)
        try appendIncidentRecord(.event(incidentID, event), configuration: configuration)
    }

    mutating func freezeIncident(
        id: String,
        frozenAtMilliseconds: Int64,
        configuration: AppObservabilityConfiguration
    ) throws {
        try appendIncidentRecord(.freeze(id, frozenAtMilliseconds), configuration: configuration)
    }

    mutating func updateIncident(
        id: String,
        status: ObservabilityIncidentStatus,
        frozenAtMilliseconds: Int64?,
        configuration: AppObservabilityConfiguration
    ) throws {
        try appendIncidentRecord(.status(id, status, frozenAtMilliseconds), configuration: configuration)
    }

    mutating func flush() throws {
        if shutdownLatched {
            guard !failureLatched else { throw ObservabilityStoreError.unavailable }
            return
        }
        guard !failureLatched else { throw ObservabilityStoreError.unavailable }
        do {
            try flushPendingWrites()
        } catch {
            latchFailure()
            throw error
        }
    }

    mutating func removeAllLogs() throws {
        guard !shutdownLatched else { throw ObservabilityStoreError.unavailable }
        try closeThrowing()
        do {
            try fileIO.prepareDirectories()
            try reloadManifestAuthority()
            let names = Set(manifest.entries.values.filter(\.disposition.isDeletable).map(\.name))
            try beginDeletion(names, reportsIncidentRevocation: true)
            for name in names.sorted() {
                try removePendingFile(named: name)
            }
            try refreshUsage()
            failureLatched = false
        } catch {
            refreshUsageAfterFailure()
            latchFailure()
            throw error
        }
    }

    mutating func removeIncident(id: String) throws {
        guard !shutdownLatched else { throw ObservabilityStoreError.unavailable }
        do {
            try fileIO.prepareDirectories()
            try reloadManifestAuthority()
            let name = "incident-\(id).jsonl"
            guard let entry = manifest.entry(named: name) else { throw ObservabilityStoreError.openFailed }
            guard entry.disposition != .readOnly else { throw ObservabilityStoreError.readOnly }
            try beginDeletion([name], reportsIncidentRevocation: true)
            try removePendingFile(named: name)
            try refreshUsage()
            failureLatched = false
        } catch {
            refreshUsageAfterFailure()
            latchFailure()
            throw error
        }
    }

    mutating func takeIncidentPersistenceChanges() -> ObservabilityIncidentPersistenceChanges {
        defer { readOnlyIncidentIDs.removeAll(keepingCapacity: true) }
        return ObservabilityIncidentPersistenceChanges(readOnlyIDs: readOnlyIncidentIDs)
    }

    mutating func close() {
        try? handle?.close()
        handle = nil
        currentURL = nil
        currentSize = 0
        available = false
    }

    mutating func closeThrowing() throws {
        let closingHandle = handle
        handle = nil
        currentURL = nil
        currentSize = 0
        available = false
        try closingHandle?.close()
    }

    mutating func shutdown() throws {
        if shutdownLatched {
            guard !failureLatched else { throw ObservabilityStoreError.unavailable }
            return
        }
        shutdownLatched = true
        var firstError: Error?
        do {
            guard !failureLatched else { throw ObservabilityStoreError.unavailable }
            try flushPendingWrites()
        } catch {
            firstError = error
        }
        do {
            try closeThrowing()
        } catch {
            if firstError == nil { firstError = error }
        }
        if let firstError {
            failureLatched = true
            throw firstError
        }
    }
}

private extension RollingObservabilityStore {
    mutating func flushPendingWrites() throws {
        try handle?.synchronize()
    }

    mutating func appendIncidentRecord(
        _ record: ObservabilityIncidentRecord,
        configuration: AppObservabilityConfiguration
    ) throws {
        guard configuration.mode.persistsToDisk else { return }
        guard !failureLatched, !shutdownLatched else { throw ObservabilityStoreError.unavailable }
        do {
            let incidentURL = try fileIO.incidentURL(id: record.incidentID)
            try ensurePrepared(configuration: configuration, protectedURLs: [incidentURL])
            let name = "incident-\(record.incidentID).jsonl"
            guard let entry = manifest.entry(named: name) else { throw ObservabilityStoreError.openFailed }
            guard entry.disposition == .managed,
                  let committedBytes = entry.committedBytes,
                  let journalState = incidentJournalStates[record.incidentID]
            else { throw ObservabilityStoreError.readOnly }
            let nextJournalState = try codec.nextIncidentJournalState(
                appending: record,
                to: journalState
            )
            let data = try codec.encodedRecord(record)
            let bytes = try ObservabilityStoreArithmetic.bytes(data.count)
            let size = try fileIO.regularFileSize(incidentURL)
            guard size == committedBytes else { throw ObservabilityStoreError.unsafePath }
            let nextCommittedBytes = try ObservabilityStoreArithmetic.adding(committedBytes, bytes)
            guard nextCommittedBytes <= Self.maximumIncidentBytes else {
                throw ObservabilityStoreError.incidentTooLarge
            }
            try makeRoom(
                for: bytes,
                configuration: configuration,
                protectedURLs: protectedCurrentFile.union([incidentURL])
            )
            let nextUsage = try ObservabilityStoreArithmetic.adding(usageBytes, bytes)
            let nextManagedUsage = try ObservabilityStoreArithmetic.adding(managedUsageBytes, bytes)
            do {
                try persistIncidentAppend(
                    data,
                    record: record,
                    name: name,
                    committedBytes: committedBytes,
                    nextCommittedBytes: nextCommittedBytes
                )
            } catch {
                try? markIncidentReadOnly(id: record.incidentID)
                throw error
            }
            incidentJournalStates[record.incidentID] = nextJournalState
            usageBytes = nextUsage
            managedUsageBytes = nextManagedUsage
        } catch {
            refreshUsageAfterFailure()
            latchFailure()
            throw error
        }
    }

    mutating func persistIncidentAppend(
        _ data: Data,
        record: ObservabilityIncidentRecord,
        name: String,
        committedBytes: Int64,
        nextCommittedBytes: Int64
    ) throws {
        let appendedBytes = try fileIO.appendIncident(
            data,
            id: record.incidentID,
            expectedCommittedBytes: committedBytes
        ) { descriptor in
            try durabilityOperations.synchronizeIncident(descriptor, record.incidentID)
        }
        guard appendedBytes == nextCommittedBytes else {
            throw ObservabilityStoreError.unsafePath
        }
        let result = try persistManifestMutation {
            try $0.commitIncidentBytes(
                name,
                from: committedBytes,
                to: nextCommittedBytes
            )
        }
        try result.requireDurable()
    }

    mutating func ensurePrepared(
        configuration: AppObservabilityConfiguration,
        protectedURLs: Set<URL> = []
    ) throws {
        if handle == nil, !available {
            try prepare(configuration: configuration, protectedURLs: protectedURLs)
        }
    }

    mutating func rotateIfNeeded(
        adding bytes: Int64,
        configuration: AppObservabilityConfiguration
    ) throws {
        let rotationBytes = ObservabilityStorePolicy.rotationLimit(
            configuration: configuration,
            override: rotationBytesOverride
        )
        let projected = try ObservabilityStoreArithmetic.adding(currentSize, bytes)
        guard currentSize > 0, projected > rotationBytes else { return }
        close()
        lastRotationAtMilliseconds = ObservabilityStorePolicy.milliseconds(now())
        try openNewFile()
    }

    mutating func makeRoom(
        for additionalBytes: Int64,
        configuration: AppObservabilityConfiguration,
        protectedURLs: Set<URL>
    ) throws {
        try refreshUsage()
        guard additionalBytes <= configuration.diskBudgetBytes else {
            throw ObservabilityStoreError.budgetExceeded
        }
        let projected = try ObservabilityStoreArithmetic.adding(usageBytes, additionalBytes)
        guard projected > configuration.diskBudgetBytes else { return }
        try enforceRetention(
            configuration: configuration,
            requiredBytes: additionalBytes,
            protectedURLs: protectedURLs
        )
    }

    mutating func openNewFile() throws {
        var name = ""
        try refreshPhysicalOccupancy()
        try persistManifestMutation { state in
            name = try state.reserveEventFileName()
        }.requireDurable()
        var newHandle: FileHandle?
        do {
            let created = try fileIO.createEventFile(named: name)
            newHandle = created.1
            try persistManifestMutation { try $0.markManaged(name) }.requireDurable()
            handle = created.1
            currentURL = created.0
            currentSize = 0
            available = true
        } catch {
            try? newHandle?.close()
            abandonCreation(named: name)
            throw error
        }
    }

    var protectedCurrentFile: Set<URL> {
        currentURL.map { [$0] } ?? []
    }

    mutating func refreshUsageAfterFailure() {
        try? refreshUsage()
    }

    mutating func latchFailure() {
        for entry in manifest.matchingEntries(kind: .incident, where: { $0 == .managed }) {
            if let id = fileIO.incidentID(for: URL(fileURLWithPath: entry.name)) {
                readOnlyIncidentIDs.insert(id)
            }
        }
        incidentJournalStates.removeAll(keepingCapacity: true)
        close()
        failureLatched = true
    }
}
