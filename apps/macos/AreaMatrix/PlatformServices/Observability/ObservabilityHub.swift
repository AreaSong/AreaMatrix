import Foundation

actor ObservabilityHub {
    private let systemLogSink = ObservabilitySystemLogSink()
    private let configurationStore: ObservabilityConfigurationStore
    let sessionID: String
    private let now: @Sendable () -> Date
    private let monotonicNow: @Sendable () -> UInt64
    private let idGenerator: @Sendable () -> String
    private let signpostSink: ObservabilitySignpostSink
    private let catalog: ObservabilityCatalog?
    private let catalogFailureReason: String?
    private var expectedCoreBuildContext: ObservabilityBuildContextSnapshot?
    var configuration: AppObservabilityConfiguration
    private var memoryEvents = ObservabilityEventRing()
    var writer: RollingObservabilityStore
    var incidentLedger = ObservabilityIncidentLedger()
    var writerFailureReason: String?
    private var ingressFailureReason: String?
    private var resourceIdentityFailureReason: String?
    private var localSequence: UInt64 = 0
    private var ingressDropped: UInt64 = 0
    private var rejectedEvents: UInt64 = 0
    private var acceptingEvents = true

    init(
        configurationStore: ObservabilityConfigurationStore = ObservabilityConfigurationStore(),
        rootURL: URL? = nil,
        writer: RollingObservabilityStore? = nil,
        sessionID: String = ObservabilityProcessIdentity.sessionID,
        expectedCoreBuildContext: ObservabilityBuildContextSnapshot? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        monotonicNow: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
        idGenerator: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() },
        signpostSink: ObservabilitySignpostSink = ObservabilitySignpostSink(),
        catalogResult: Result<ObservabilityCatalog, ObservabilityCatalogError> =
            ObservabilityCatalog.loadBundled()
    ) {
        self.configurationStore = configurationStore
        self.sessionID = sessionID
        self.expectedCoreBuildContext = expectedCoreBuildContext
        self.now = now
        self.monotonicNow = monotonicNow
        self.idGenerator = idGenerator
        self.signpostSink = signpostSink
        switch catalogResult {
        case let .success(catalog):
            self.catalog = catalog
            catalogFailureReason = nil
        case .failure:
            catalog = nil
            catalogFailureReason = "catalog-unavailable"
        }
        configuration = configurationStore.load()
        self.writer = writer ?? RollingObservabilityStore(rootURL: rootURL, now: now)
    }

    func configurationSnapshot() -> AppObservabilityConfiguration {
        configuration
    }

    func sessionIDSnapshot() -> String {
        sessionID
    }

    func storageRootURLSnapshot() -> URL? {
        writer.storageRootURL
    }

    func catalogSnapshot() -> ObservabilityCatalog? {
        catalog
    }

    func stopAcceptingEvents() {
        acceptingEvents = false
    }

    func configureCoreBuildContext(_ context: ObservabilityBuildContextSnapshot) -> Bool {
        guard acceptingEvents,
              expectedCoreBuildContext == nil || expectedCoreBuildContext == context,
              case .success = ObservabilitySafetyPolicy.validate(
                  buildContext: context,
                  schemaVersion: 2,
                  scope: .liveCore(expected: context)
              )
        else {
            ingressFailureReason = "core-build-context-invalid"
            return false
        }
        expectedCoreBuildContext = context
        return true
    }

    func configure(_ newConfiguration: AppObservabilityConfiguration) {
        guard acceptingEvents else {
            ObservabilityHubPolicy.increment(&rejectedEvents)
            return
        }
        let normalized = ObservabilityHubPolicy.normalized(newConfiguration)
        if configuration.mode.persistsToDisk, !normalized.mode.persistsToDisk {
            do {
                try freezeActiveIncidentForShutdown(at: ObservabilityHubPolicy.milliseconds(now()))
            } catch {
                writerFailureReason = "writer-unavailable"
                return
            }
        }
        configuration = normalized
        memoryEvents.setCapacity(configuration.observabilityMemoryCapacity)
        configurationStore.save(configuration)
        do {
            defer { incidentLedger.reconcilePersistenceChanges(from: &writer) }
            try writer.prepare(configuration: configuration)
            writerFailureReason = nil
        } catch {
            writerFailureReason = "writer-unavailable"
            return
        }
        recoverIncidentsIfNeeded()
    }

    func ingestCoreEvent(_ event: ObservabilityEventSnapshot) {
        guard acceptingEvents else {
            ObservabilityHubPolicy.increment(&rejectedEvents)
            return
        }
        guard event.sessionID == sessionID else {
            ObservabilityHubPolicy.increment(&rejectedEvents)
            ingressFailureReason = "session-mismatch"
            return
        }
        guard let expectedCoreBuildContext,
              case .success = ObservabilitySafetyPolicy.validate(
                  buildContext: event.buildContext,
                  schemaVersion: event.schemaVersion,
                  scope: .liveCore(expected: expectedCoreBuildContext)
              )
        else {
            ObservabilityHubPolicy.increment(&rejectedEvents)
            ingressFailureReason = "core-build-context-mismatch"
            return
        }
        ingest(event, buildScope: .liveCore(expected: expectedCoreBuildContext))
    }

    func recordSemanticAction(_ input: ObservabilitySemanticEventInput) {
        guard acceptingEvents else {
            ObservabilityHubPolicy.increment(&rejectedEvents)
            return
        }
        ObservabilityHubPolicy.increment(&localSequence)
        let timestamp = ObservabilityHubPolicy.milliseconds(now())
        let incidentID = input.incidentID ?? incidentLedger.activeID(at: timestamp)
        ingest(ObservabilityHubEventFactory.semanticEvent(
            input,
            context: .init(
                eventID: idGenerator(),
                timestamp: timestamp,
                monotonicTimestamp: monotonicNow(),
                sequenceNumber: localSequence,
                sessionID: sessionID,
                incidentID: incidentID
            )
        ), buildScope: .liveApp)
    }

    func recentEvents(limit: Int = 1000) -> [ObservabilityEventSnapshot] {
        memoryEvents.suffix(limit)
    }

    func noteIngressDrop(count: UInt64 = 1) {
        guard acceptingEvents else { return }
        ingressDropped = ObservabilityHubPolicy.saturatingSum([ingressDropped, count])
        ingressFailureReason = "ingress-overflow"
    }

    func noteResourceIdentityDegraded(reason: String) {
        guard acceptingEvents else { return }
        resourceIdentityFailureReason = reason
    }

    func markIncident(note: String?) -> String {
        guard acceptingEvents else {
            ObservabilityHubPolicy.increment(&rejectedEvents)
            return ""
        }
        let timestamp = ObservabilityHubPolicy.milliseconds(now())
        let incidentID = ObservabilityHubPolicy.safeIdentifier(idGenerator())
        guard incidentLedger.canBegin(id: incidentID) else {
            ObservabilityHubPolicy.increment(&rejectedEvents)
            return ""
        }
        if incidentLedger.hasActiveIncident {
            let frozenAt = incidentLedger.expiredFreezeTimestamp(at: timestamp) ?? timestamp
            guard freezeActiveIncident(at: frozenAt) else {
                ObservabilityHubPolicy.increment(&rejectedEvents)
                return ""
            }
        }

        let snapshot = ObservabilityHubEventFactory.incident(.init(
            id: incidentID,
            sessionID: sessionID,
            markedAt: timestamp,
            note: note,
            events: memoryEvents.elements(),
            capacity: configuration.observabilityMemoryCapacity
        ))
        guard incidentLedger.begin(snapshot, activate: true) else {
            ObservabilityHubPolicy.increment(&rejectedEvents)
            return ""
        }
        persistNewIncident(snapshot)
        return snapshot.id
    }

    func updateIncident(id: String, status: String) throws {
        guard acceptingEvents else { throw IncidentError.runtimeStopped }
        guard let newStatus = ObservabilityIncidentStatus(rawValue: status) else {
            throw IncidentError.invalidStatus
        }
        freezeExpiredIncident(at: ObservabilityHubPolicy.milliseconds(now()))
        let timestamp = ObservabilityHubPolicy.milliseconds(now())
        guard let change = incidentLedger.statusChange(id: id, status: newStatus, at: timestamp) else {
            throw IncidentError.notFound
        }
        switch change.disposition {
        case .memoryOnly:
            break
        case .readOnly:
            throw IncidentError.readOnly
        case .manifestOwned:
            guard configuration.mode.persistsToDisk else {
                throw IncidentError.persistenceUnavailable
            }
            do {
                defer { incidentLedger.reconcilePersistenceChanges(from: &writer) }
                try writer.updateIncident(
                    id: id,
                    status: newStatus,
                    frozenAtMilliseconds: change.frozenAtMilliseconds,
                    configuration: configuration
                )
                recordWriterMutationResult()
            } catch {
                writerFailureReason = "writer-unavailable"
                throw IncidentError.persistenceUnavailable
            }
        }
        incidentLedger.apply(change)
    }

    func incidentSnapshots() -> [ObservabilityIncidentSnapshot] {
        incidentLedger.projectedSnapshots(at: ObservabilityHubPolicy.milliseconds(now()))
    }

    func activeIncidentID() -> String? {
        incidentLedger.activeID(at: ObservabilityHubPolicy.milliseconds(now()))
    }

    func removeLocalLogs() throws {
        guard acceptingEvents else { throw ObservabilityStoreError.unavailable }
        do {
            defer { incidentLedger.reconcilePersistenceChanges(from: &writer) }
            try writer.removeAllLogs()
            writerFailureReason = nil
        } catch {
            writerFailureReason = "writer-unavailable"
            throw error
        }
        memoryEvents.removeAll()
        incidentLedger.clearWritableIncidents()
    }

    func deleteIncident(id: String) throws {
        guard acceptingEvents else { throw IncidentError.runtimeStopped }
        guard let disposition = incidentLedger.removalDisposition(id: id) else {
            throw IncidentError.notFound
        }
        switch disposition {
        case .memoryOnly:
            break
        case .readOnly:
            throw IncidentError.readOnly
        case .manifestOwned:
            guard configuration.mode.persistsToDisk else {
                throw IncidentError.persistenceUnavailable
            }
            do {
                defer { incidentLedger.reconcilePersistenceChanges(from: &writer) }
                try writer.removeIncident(id: id)
                writerFailureReason = nil
            } catch {
                writerFailureReason = "writer-unavailable"
                throw IncidentError.persistenceUnavailable
            }
        }
        incidentLedger.applyRemoval(id: id)
    }

    @discardableResult
    func recoverInterruptedSession(
        previousSessionID: String,
        nowMilliseconds: Int64
    ) -> String? {
        guard acceptingEvents else {
            ObservabilityHubPolicy.increment(&rejectedEvents)
            return nil
        }
        guard previousSessionID != sessionID else { return nil }
        let recent: [ObservabilityEventSnapshot]
        do {
            recent = try writer.loadRecentEvents(limit: configuration.observabilityMemoryCapacity)
                .filter { $0.sessionID == previousSessionID }
                .compactMap { sanitized($0, buildScope: .diagnosticPackage) }
        } catch {
            writerFailureReason = "session-recovery-unavailable"
            return nil
        }
        let snapshot = ObservabilityHubEventFactory.recoveredIncident(.init(
            id: ObservabilityHubPolicy.safeIdentifier(idGenerator()),
            previousSessionID: previousSessionID,
            nowMilliseconds: nowMilliseconds,
            events: recent
        ))
        guard incidentLedger.begin(snapshot, activate: false) else {
            ObservabilityHubPolicy.increment(&rejectedEvents)
            return nil
        }
        persistNewIncident(snapshot)
        return snapshot.id
    }

    func flush() throws {
        freezeExpiredIncident(at: ObservabilityHubPolicy.milliseconds(now()))
        do {
            defer { incidentLedger.reconcilePersistenceChanges(from: &writer) }
            try writer.flush()
        } catch {
            writerFailureReason = "writer-unavailable"
            throw error
        }
    }

    func shutdown() throws {
        acceptingEvents = false
        signpostSink.reset()
        let timestamp = ObservabilityHubPolicy.milliseconds(now())
        var firstError: Error?
        do {
            try freezeActiveIncidentForShutdown(at: timestamp)
        } catch {
            firstError = error
        }
        do {
            defer { incidentLedger.reconcilePersistenceChanges(from: &writer) }
            try writer.shutdown()
        } catch {
            if firstError == nil { firstError = error }
        }
        if let firstError {
            writerFailureReason = "writer-close-failed"
            throw firstError
        }
    }

    func health(core: ObservabilityHealth?) -> AppObservabilityHealth {
        let timestamp = ObservabilityHubPolicy.milliseconds(now())
        return ObservabilityHubPolicy.makeHealth(state: ObservabilityHubHealthState(
            configuration: configuration,
            memoryEventCount: memoryEvents.count,
            memoryCapacity: configuration.observabilityMemoryCapacity,
            oldestEventTimestampMilliseconds: memoryEvents.first?.wallTimestampMilliseconds,
            fileUsageBytes: writer.usageBytes,
            writerAvailable: writer.available,
            lastRotationAtMilliseconds: writer.lastRotationAtMilliseconds,
            incidentCount: incidentLedger.count,
            activeIncidentID: incidentLedger.activeID(at: timestamp),
            catalogFailureReason: catalogFailureReason,
            writerFailureReason: writerFailureReason,
            resourceIdentityFailureReason: resourceIdentityFailureReason,
            ingressFailureReason: ingressFailureReason,
            signpostRejectedIntervalCount: signpostSink.health().rejectedIntervalCount,
            ingressDroppedEvents: ingressDropped,
            rejectedEvents: rejectedEvents
        ), core: core)
    }
}

extension ObservabilityHub {
    private func ingest(
        _ rawEvent: ObservabilityEventSnapshot,
        buildScope: ObservabilitySafetyPolicy.BuildScope
    ) {
        guard ObservabilityHubPolicy.isEnabled(
            rawEvent.severity,
            minimumSeverity: configuration.minimumSeverity
        ), let event = sanitized(rawEvent, buildScope: buildScope) else { return }
        let timestamp = ObservabilityHubPolicy.milliseconds(now())
        freezeExpiredIncident(at: timestamp)
        memoryEvents.append(event, capacity: configuration.observabilityMemoryCapacity)
        captureForActiveIncident(event, at: timestamp)
        signpostSink.consume(event)
        systemLogSink.consume(event)
        guard configuration.mode.persistsToDisk else { return }
        do {
            defer { incidentLedger.reconcilePersistenceChanges(from: &writer) }
            try writer.append(event, configuration: configuration)
            recordWriterMutationResult()
        } catch {
            writerFailureReason = "writer-unavailable"
        }
    }

    func sanitized(
        _ rawEvent: ObservabilityEventSnapshot,
        buildScope: ObservabilitySafetyPolicy.BuildScope
    ) -> ObservabilityEventSnapshot? {
        let event = ObservabilityHubEventFactory.sanitized(
            rawEvent,
            includeSensitive: configuration.includeSensitive,
            catalog: catalog,
            buildScope: buildScope
        )
        if event == nil { ObservabilityHubPolicy.increment(&rejectedEvents) }
        return event
    }
}
