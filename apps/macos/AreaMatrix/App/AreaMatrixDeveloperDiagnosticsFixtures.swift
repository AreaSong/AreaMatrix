import Foundation

#if DEBUG
enum DeveloperDiagnosticsScenarioFixture {
    static let sessionID = "developer-diagnostics-session"

    static let coreBuildContext = ObservabilityBuildContextSnapshot(
        producer: "area_matrix_core",
        version: "0.1.0",
        build: nil,
        configuration: "debug",
        platform: "macos",
        architecture: "aarch64"
    )

    static let configuration = AppObservabilityConfiguration(
        mode: .developer,
        minimumSeverity: .debug,
        diskBudgetBytes: 250 * 1024 * 1024,
        retentionHours: 48,
        includeSensitive: false,
        modeLease: AppObservabilityModeLease(
            policy: .manual,
            activatedAtMilliseconds: 1_778_738_100_000,
            activationSessionID: sessionID,
            expiresAtMilliseconds: nil
        )
    )

    static let events: [ObservabilityEventSnapshot] = [
        event(.init(
            id: "developer-event-01",
            sequence: 1,
            actionID: "repository.import.confirmed",
            componentID: "macos.import.progress",
            layer: "swift_ui",
            phase: "started",
            outcome: "started",
            duration: nil
        )),
        event(.init(
            id: "developer-event-02",
            sequence: 2,
            actionID: "repository.import.validation",
            componentID: "macos.import.bridge",
            layer: "bridge",
            phase: "completed",
            outcome: "succeeded",
            duration: 18
        )),
        event(.init(
            id: "developer-event-03",
            sequence: 3,
            actionID: "repository.import.staging",
            componentID: "core.storage.import",
            layer: "filesystem",
            phase: "completed",
            outcome: "succeeded",
            duration: 42
        )),
        event(.init(
            id: "developer-event-04",
            sequence: 4,
            actionID: "repository.import.db_promotion",
            componentID: "core.storage.import",
            layer: "database",
            phase: "completed",
            outcome: "succeeded",
            duration: 11
        )),
        event(.init(
            id: "developer-event-05",
            sequence: 5,
            actionID: "repository.import.overview",
            componentID: "core.storage.overview",
            layer: "core",
            phase: "completed",
            outcome: "degraded",
            duration: 27,
            severity: .warn,
            error: ObservabilityErrorSnapshot(
                code: "overview-refresh-deferred",
                kind: "io",
                technicalDetails: "Generated overview refresh will retry from the committed metadata state."
            )
        )),
        event(.init(
            id: "developer-event-06",
            sequence: 6,
            actionID: "repository.import.confirmed",
            componentID: "macos.import.result",
            layer: "swift_ui",
            phase: "completed",
            outcome: "succeeded",
            duration: 103
        ))
    ]

    static let incident = ObservabilityIncidentSnapshot(
        id: "developer-incident-01",
        sessionID: sessionID,
        markedAtMilliseconds: 1_778_738_400_000,
        captureEndsAtMilliseconds: 1_778_738_430_000,
        status: .open,
        note: "Import completed with a deferred overview refresh.",
        events: events,
        isFrozen: true,
        recoveredAfterRestart: false
    )

    static var packagePreviewSummary: DiagnosticsPackagePreviewSummary {
        do {
            let preview = try DiagnosticPackageExporter().preview(
                events: events,
                privacySelection: .redacted,
                summary: "Local developer scenario package preview."
            )
            return DiagnosticsPackagePreviewSummary(preview)
        } catch {
            preconditionFailure("Developer diagnostics package fixture is invalid: \(error)")
        }
    }

    static var catalog: ObservabilityCatalog? {
        switch ObservabilityCatalog.loadBundled() {
        case let .success(catalog):
            catalog
        case .failure:
            nil
        }
    }

    static let semanticInputs: [ObservabilitySemanticEventInput] = {
        var started = ObservabilitySemanticEventInput(
            actionID: "repository.import.confirmed",
            componentID: "macos.import.progress"
        )
        started.traceID = "developer-settings-trace"
        started.operationID = "developer-settings-operation"
        started.phase = "started"
        started.outcome = "started"

        var completed = ObservabilitySemanticEventInput(
            actionID: "repository.import.confirmed",
            componentID: "macos.import.result"
        )
        completed.traceID = started.traceID
        completed.operationID = started.operationID
        completed.phase = "completed"
        completed.outcome = "succeeded"
        completed.durationMilliseconds = 103
        return [started, completed]
    }()

    private static func event(_ fixture: EventFixture) -> ObservabilityEventSnapshot {
        ObservabilityEventSnapshot(
            schemaVersion: 2,
            eventID: fixture.id,
            wallTimestampMilliseconds: 1_778_738_400_000 + Int64(fixture.sequence * 100),
            monotonicTimestampNanoseconds: fixture.sequence * 100_000_000,
            sequenceNumber: fixture.sequence,
            sessionID: sessionID,
            incidentID: incidentID(for: fixture.sequence),
            traceID: "developer-import-trace",
            spanID: "developer-span-\(fixture.sequence)",
            parentSpanID: fixture.sequence == 1 ? nil : "developer-span-\(fixture.sequence - 1)",
            operationID: "developer-import-operation",
            retryOfOperationID: nil,
            actionID: fixture.actionID,
            componentID: fixture.componentID,
            layer: fixture.layer,
            phase: fixture.phase,
            severity: fixture.severity,
            outcome: fixture.outcome,
            durationMilliseconds: fixture.duration,
            resources: [
                ObservabilityResourceSnapshot(
                    resourceID: "developer-file",
                    alias: "file.0123456789abcdef01234567",
                    pathExtension: "pdf",
                    sizeBucket: "small",
                    storageMode: "copied"
                )
            ],
            error: fixture.error,
            attributes: [
                ObservabilityAttributeSnapshot(
                    key: "obs_public_item_count",
                    value: "3",
                    privacy: "public"
                )
            ],
            privacy: "pseudonymous",
            message: nil,
            target: "developer-scenario",
            threadName: "main",
            buildContext: coreBuildContext
        )
    }

    private static func incidentID(for sequence: UInt64) -> String? {
        sequence >= 3 ? "developer-incident-01" : nil
    }

    private struct EventFixture {
        let id: String
        let sequence: UInt64
        let actionID: String
        let componentID: String
        let layer: String
        let phase: String
        let outcome: String
        let duration: UInt64?
        var severity: AppObservabilitySeverity = .info
        var error: ObservabilityErrorSnapshot?
    }
}

actor DeveloperDiagnosticsCoreFixture: CoreObservabilityControlling {
    func observabilityBuildContext() async -> ObservabilityBuildContextSnapshot {
        DeveloperDiagnosticsScenarioFixture.coreBuildContext
    }

    func initializeObservability(
        config: CoreObservabilityConfigurationSnapshot,
        sink _: any CoreObservabilityEventSinking
    ) async throws -> CoreObservabilityHealthSnapshot {
        health(mode: config.mode)
    }

    func updateObservability(
        config: CoreObservabilityConfigurationSnapshot
    ) async throws -> CoreObservabilityHealthSnapshot {
        health(mode: config.mode)
    }

    func observabilityHealth() async -> CoreObservabilityHealthSnapshot {
        health(mode: .developer)
    }

    func flushObservability(deadlineMilliseconds _: UInt64) async throws -> CoreObservabilityHealthSnapshot {
        health(mode: .developer)
    }

    private func health(mode: CoreObservabilityModeSnapshot) -> CoreObservabilityHealthSnapshot {
        CoreObservabilityHealthSnapshot(
            initialized: true,
            mode: mode,
            queueDepth: 2,
            queueCapacity: 4096,
            droppedTrace: 3,
            droppedDebug: 0,
            droppedInfo: 0,
            droppedWarn: 0,
            droppedError: 0,
            redactionRejected: 1,
            callbackConnected: true,
            degraded: false,
            degradedReason: nil
        )
    }
}

actor DeveloperDiagnosticsIncidentFixture: DiagnosticsIncidentManaging {
    private var snapshots = [DeveloperDiagnosticsScenarioFixture.incident]
    private var nextID = 2

    func markIncident(note: String?) -> String {
        let id = "developer-incident-\(String(format: "%02d", nextID))"
        nextID += 1
        snapshots.append(ObservabilityIncidentSnapshot(
            id: id,
            sessionID: DeveloperDiagnosticsScenarioFixture.sessionID,
            markedAtMilliseconds: 1_778_738_500_000 + Int64(nextID),
            captureEndsAtMilliseconds: 1_778_738_530_000 + Int64(nextID),
            status: .open,
            note: note,
            events: DeveloperDiagnosticsScenarioFixture.events,
            isFrozen: true,
            recoveredAfterRestart: false
        ))
        return id
    }

    func updateIncident(id: String, status: String) throws {
        guard let index = snapshots.firstIndex(where: { $0.id == id }),
              let resolved = ObservabilityIncidentStatus(rawValue: status)
        else { return }
        snapshots[index].status = resolved
    }

    func deleteIncident(id: String) {
        snapshots.removeAll { $0.id == id }
    }

    func incidentSnapshots() -> [ObservabilityIncidentSnapshot] {
        snapshots
    }
}

actor DeveloperDiagnosticsPackagePreviewer: DiagnosticsPackagePreviewing {
    func makePreview(
        events: [ObservabilityEventSnapshot],
        privacySelection: DiagnosticPackagePrivacySelection,
        repositoryURL _: URL?,
        summary: String
    ) throws -> DiagnosticPackagePreview {
        try DiagnosticPackageExporter().preview(
            events: events,
            privacySelection: privacySelection,
            repositoryURL: nil,
            summary: summary
        )
    }
}

@MainActor
struct DeveloperDiagnosticsPackageHandler: DiagnosticsPackageHandling {
    func export(
        _: DiagnosticPackagePreview,
        suggestedFileName _: String
    ) throws -> URL? {
        nil
    }

    func openPackage() throws -> DiagnosticPackageInspection? {
        nil
    }
}
#endif
