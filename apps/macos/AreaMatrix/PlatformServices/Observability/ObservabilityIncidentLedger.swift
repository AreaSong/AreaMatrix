import Foundation

struct ObservabilityIncidentLedger {
    private static let maximumIncidentCount = 20

    private(set) var snapshots: [ObservabilityIncidentSnapshot] = []
    private(set) var activeID: String?
    private var persistenceByID: [String: PersistenceDisposition] = [:]
    private(set) var isLoaded = false

    var count: Int {
        snapshots.count
    }

    var hasActiveIncident: Bool {
        activeID != nil
    }

    func canBegin(id: String) -> Bool {
        !snapshots.contains(where: { $0.id == id }) && persistenceByID[id] == nil
    }

    func activeID(at timestamp: Int64) -> String? {
        guard let activeID,
              let incident = snapshots.first(where: { $0.id == activeID }),
              persistenceByID[activeID] != nil,
              timestamp <= incident.captureEndsAtMilliseconds
        else { return nil }
        return activeID
    }

    func projectedSnapshots(at timestamp: Int64) -> [ObservabilityIncidentSnapshot] {
        snapshots.map { incident in
            guard incident.id == activeID,
                  timestamp > incident.captureEndsAtMilliseconds
            else { return incident }
            var projected = incident
            projected.isFrozen = true
            return projected
        }
    }

    func statusChange(
        id: String,
        status: ObservabilityIncidentStatus,
        at timestamp: Int64
    ) -> StatusChange? {
        guard snapshots.contains(where: { $0.id == id }), let disposition = persistenceByID[id] else {
            return nil
        }
        let frozenAt = status == .open ? nil : timestamp
        return StatusChange(
            id: id,
            status: status,
            frozenAtMilliseconds: frozenAt,
            disposition: disposition
        )
    }

    func freezePlan(at timestamp: Int64, truncatingWindow: Bool) -> FreezePlan? {
        guard let activeID,
              let incident = snapshots.first(where: { $0.id == activeID }),
              let disposition = persistenceByID[activeID]
        else { return nil }
        let frozenAt = truncatingWindow
            ? min(timestamp, incident.captureEndsAtMilliseconds)
            : timestamp
        return FreezePlan(
            id: activeID,
            frozenAtMilliseconds: frozenAt,
            disposition: disposition
        )
    }

    func expiredFreezeTimestamp(at timestamp: Int64) -> Int64? {
        guard let activeID,
              let incident = snapshots.first(where: { $0.id == activeID }),
              timestamp > incident.captureEndsAtMilliseconds
        else { return nil }
        return incident.captureEndsAtMilliseconds
    }

    @discardableResult
    mutating func begin(
        _ snapshot: ObservabilityIncidentSnapshot,
        activate: Bool,
        disposition: PersistenceDisposition = .memoryOnly
    ) -> Bool {
        guard canBegin(id: snapshot.id) else { return false }
        snapshots.append(snapshot)
        persistenceByID[snapshot.id] = disposition
        if activate { activeID = snapshot.id }
        trimToLimit()
        return true
    }

    func capturePlan(
        _ rawEvent: ObservabilityEventSnapshot,
        at timestamp: Int64,
        capacity: Int
    ) -> CapturePlan? {
        guard let activeID,
              let incident = snapshots.first(where: { $0.id == activeID }),
              let disposition = persistenceByID[activeID],
              timestamp <= incident.captureEndsAtMilliseconds
        else { return nil }
        var event = rawEvent
        event.incidentID = activeID
        return CapturePlan(
            incidentID: activeID,
            event: event,
            capacity: capacity,
            disposition: disposition
        )
    }

    mutating func apply(_ plan: CapturePlan) {
        guard let index = snapshots.firstIndex(where: { $0.id == plan.incidentID }) else { return }
        snapshots[index].events.append(plan.event)
        let overflow = snapshots[index].events.count - max(0, plan.capacity)
        if overflow > 0 { snapshots[index].events.removeFirst(overflow) }
    }

    mutating func apply(_ change: StatusChange) {
        guard let index = snapshots.firstIndex(where: { $0.id == change.id }) else { return }
        snapshots[index].status = change.status
        guard let frozenAt = change.frozenAtMilliseconds else { return }
        snapshots[index].captureEndsAtMilliseconds = min(
            snapshots[index].captureEndsAtMilliseconds,
            frozenAt
        )
        snapshots[index].isFrozen = true
        activeID = nil
    }

    mutating func apply(_ plan: FreezePlan) {
        guard let index = snapshots.firstIndex(where: { $0.id == plan.id }) else { return }
        snapshots[index].captureEndsAtMilliseconds = min(
            snapshots[index].captureEndsAtMilliseconds,
            plan.frozenAtMilliseconds
        )
        snapshots[index].isFrozen = true
        activeID = nil
    }

    mutating func markPersistence(_ disposition: PersistenceDisposition, for id: String) {
        guard let index = snapshots.firstIndex(where: { $0.id == id }) else { return }
        persistenceByID[id] = disposition
        if disposition == .readOnly {
            snapshots[index].isFrozen = true
            if activeID == id { activeID = nil }
        }
    }

    mutating func reconcilePersistenceChanges(from store: inout RollingObservabilityStore) {
        let changes = store.takeIncidentPersistenceChanges()
        for id in changes.readOnlyIDs {
            markPersistence(.readOnly, for: id)
        }
    }

    mutating func mergeRecovered(_ recovered: [ObservabilityRecoveredIncident]) {
        let recoveredIDs = Set(recovered.map(\.snapshot.id))
        let memoryOnly = snapshots.filter { !recoveredIDs.contains($0.id) }
        let recoveredSnapshots = recovered.map { incident in
            var snapshot = incident.snapshot
            if incident.disposition == .readOnly { snapshot.isFrozen = true }
            return snapshot
        }
        snapshots = Array((recoveredSnapshots + memoryOnly).suffix(Self.maximumIncidentCount))
        let retainedIDs = Set(snapshots.map(\.id))
        var resolved = persistenceByID.filter { retainedIDs.contains($0.key) }
        for incident in recovered where retainedIDs.contains(incident.snapshot.id) {
            resolved[incident.snapshot.id] = incident.disposition
        }
        persistenceByID = resolved
        if let activeID, !retainedIDs.contains(activeID) { self.activeID = nil }
        isLoaded = true
    }

    func removalDisposition(id: String) -> PersistenceDisposition? {
        guard snapshots.contains(where: { $0.id == id }) else { return nil }
        return persistenceByID[id]
    }

    mutating func applyRemoval(id: String) {
        guard let index = snapshots.firstIndex(where: { $0.id == id }) else { return }
        snapshots.remove(at: index)
        persistenceByID.removeValue(forKey: id)
        if activeID == id { activeID = nil }
    }

    mutating func clear() {
        snapshots.removeAll(keepingCapacity: true)
        persistenceByID.removeAll(keepingCapacity: true)
        activeID = nil
        isLoaded = false
    }

    mutating func clearWritableIncidents() {
        let readOnlyIDs = Set(persistenceByID.compactMap { id, disposition in
            disposition == .readOnly ? id : nil
        })
        snapshots.removeAll { !readOnlyIDs.contains($0.id) }
        persistenceByID = persistenceByID.filter { readOnlyIDs.contains($0.key) }
        activeID = nil
    }
}

extension ObservabilityIncidentLedger {
    enum PersistenceDisposition: Equatable {
        case memoryOnly
        case manifestOwned
        case readOnly
    }

    struct StatusChange {
        let id: String
        let status: ObservabilityIncidentStatus
        let frozenAtMilliseconds: Int64?
        let disposition: PersistenceDisposition
    }

    struct FreezePlan {
        let id: String
        let frozenAtMilliseconds: Int64
        let disposition: PersistenceDisposition
    }

    struct CapturePlan {
        let incidentID: String
        let event: ObservabilityEventSnapshot
        let capacity: Int
        let disposition: PersistenceDisposition
    }
}

private extension ObservabilityIncidentLedger {
    mutating func trimToLimit() {
        guard snapshots.count > Self.maximumIncidentCount else { return }
        let removed = snapshots.prefix(snapshots.count - Self.maximumIncidentCount)
        for id in removed.map(\.id) {
            persistenceByID.removeValue(forKey: id)
        }
        snapshots.removeFirst(removed.count)
    }
}
