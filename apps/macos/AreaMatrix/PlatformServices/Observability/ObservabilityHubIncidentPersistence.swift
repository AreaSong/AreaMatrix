import Foundation

extension ObservabilityHub {
    func captureForActiveIncident(_ event: ObservabilityEventSnapshot, at timestamp: Int64) {
        guard let plan = incidentLedger.capturePlan(
            event,
            at: timestamp,
            capacity: configuration.observabilityMemoryCapacity
        ) else { return }
        switch plan.disposition {
        case .memoryOnly:
            incidentLedger.apply(plan)
        case .readOnly:
            return
        case .manifestOwned:
            persistCapturedEvent(plan)
        }
    }

    func persistNewIncident(_ incident: ObservabilityIncidentSnapshot) {
        guard configuration.mode.persistsToDisk else { return }
        do {
            defer { incidentLedger.reconcilePersistenceChanges(from: &writer) }
            try writer.beginIncident(incident, configuration: configuration)
            incidentLedger.markPersistence(.manifestOwned, for: incident.id)
            recordWriterMutationResult()
        } catch {
            writerFailureReason = "writer-unavailable"
        }
    }

    func freezeExpiredIncident(at timestamp: Int64) {
        guard let frozenAt = incidentLedger.expiredFreezeTimestamp(at: timestamp) else { return }
        freezeActiveIncident(at: frozenAt)
    }

    @discardableResult
    func freezeActiveIncident(at timestamp: Int64) -> Bool {
        guard let plan = incidentLedger.freezePlan(
            at: timestamp,
            truncatingWindow: false
        ) else { return !incidentLedger.hasActiveIncident }
        do {
            try commitFreezePlan(plan)
            if plan.disposition == .manifestOwned { recordWriterMutationResult() }
            return true
        } catch {
            writerFailureReason = "writer-unavailable"
            return false
        }
    }

    func freezeActiveIncidentForShutdown(at timestamp: Int64) throws {
        guard let plan = incidentLedger.freezePlan(
            at: timestamp,
            truncatingWindow: true
        ) else { return }
        try commitFreezePlan(plan)
    }

    func recoverIncidentsIfNeeded() {
        guard configuration.mode.persistsToDisk, !incidentLedger.isLoaded else { return }
        do {
            let recovered = try writer.loadRecoverableIncidents(
                currentSessionID: sessionID,
                maximumEvents: configuration.observabilityMemoryCapacity
            )
            incidentLedger.mergeRecovered(recovered.map { incident in
                ObservabilityRecoveredIncident(
                    snapshot: sanitizedRecoveredIncident(incident.snapshot),
                    disposition: incident.disposition
                )
            })
        } catch {
            writerFailureReason = "incident-recovery-unavailable"
        }
    }

    func recordWriterMutationResult() {
        writerFailureReason = writer.available ? nil : "writer-unavailable"
    }
}

private extension ObservabilityHub {
    func persistCapturedEvent(_ plan: ObservabilityIncidentLedger.CapturePlan) {
        guard configuration.mode.persistsToDisk else { return }
        do {
            defer { incidentLedger.reconcilePersistenceChanges(from: &writer) }
            try writer.appendIncidentEvent(
                plan.event,
                incidentID: plan.incidentID,
                configuration: configuration
            )
            incidentLedger.apply(plan)
            recordWriterMutationResult()
        } catch {
            writerFailureReason = "writer-unavailable"
        }
    }

    func commitFreezePlan(_ plan: ObservabilityIncidentLedger.FreezePlan) throws {
        switch plan.disposition {
        case .memoryOnly:
            incidentLedger.apply(plan)
        case .readOnly:
            return
        case .manifestOwned:
            guard configuration.mode.persistsToDisk else {
                throw ObservabilityStoreError.unavailable
            }
            defer { incidentLedger.reconcilePersistenceChanges(from: &writer) }
            try writer.freezeIncident(
                id: plan.id,
                frozenAtMilliseconds: plan.frozenAtMilliseconds,
                configuration: configuration
            )
            incidentLedger.apply(plan)
        }
    }

    func sanitizedRecoveredIncident(
        _ recovered: ObservabilityIncidentSnapshot
    ) -> ObservabilityIncidentSnapshot {
        var incident = recovered
        incident.note = ObservabilityHubPolicy.sanitizedNote(recovered.note)
        let events = recovered.events.compactMap {
            sanitized($0, buildScope: .diagnosticPackage)
        }
        incident.events = Array(events.suffix(configuration.observabilityMemoryCapacity))
        return incident
    }
}
