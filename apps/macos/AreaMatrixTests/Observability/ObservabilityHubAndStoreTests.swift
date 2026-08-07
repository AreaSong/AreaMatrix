@testable import AreaMatrix
import XCTest

final class ObservabilityHubAndStoreTests: XCTestCase {
    func testHubRejectsNormalizedCredentialVariantsAtLiveIngress() async throws {
        let fixture = try makeObservabilityFixture()
        defer { fixture.cleanup() }
        let hub = ObservabilityHub(
            configurationStore: ObservabilityConfigurationStore(defaults: fixture.defaults),
            rootURL: fixture.logsURL,
            sessionID: "credential-session",
            expectedCoreBuildContext: observabilityTestCoreBuildContext()
        )
        await hub.configure(configuration(mode: .developer, minimumSeverity: .trace))

        for (index, message) in ["Bearer\topaque", "auth = opaque", "x-api-token : opaque"].enumerated() {
            var candidate = event(
                id: "credential-\(index)",
                timestamp: Int64(index),
                sessionID: "credential-session"
            )
            candidate.message = message
            await hub.ingestCoreEvent(candidate)
        }

        let health = await hub.health(core: nil)
        let recentEvents = await hub.recentEvents(limit: 10)
        XCTAssertTrue(recentEvents.isEmpty)
        XCTAssertEqual(health.rejectedEvents, 3)
    }

    func testHubBoundsMemoryAndReportsIngressHealthForOneSession() async throws {
        let fixture = try makeObservabilityFixture()
        defer { fixture.cleanup() }
        let hub = ObservabilityHub(
            configurationStore: ObservabilityConfigurationStore(defaults: fixture.defaults),
            rootURL: fixture.logsURL,
            sessionID: "session-one",
            expectedCoreBuildContext: observabilityTestCoreBuildContext()
        )
        await hub.configure(configuration(mode: .disabled, minimumSeverity: .trace))

        for index in 0 ..< 550 {
            await hub.ingestCoreEvent(event(
                id: "event-\(index)",
                timestamp: Int64(index),
                sessionID: "session-one"
            ))
        }
        await hub.noteIngressDrop()
        await hub.ingestCoreEvent(event(id: "wrong-session", timestamp: 551, sessionID: "session-two"))

        let events = await hub.recentEvents(limit: 1000)
        let health = await hub.health(core: nil)
        let sessionID = await hub.sessionIDSnapshot()
        XCTAssertEqual(events.count, 500)
        XCTAssertEqual(events.first?.eventID, "event-50")
        XCTAssertEqual(Set(events.map(\.sessionID)), ["session-one"])
        XCTAssertEqual(sessionID, "session-one")
        XCTAssertEqual(health.memoryCapacity, 500)
        XCTAssertEqual(health.ingressDroppedEvents, 1)
        XCTAssertEqual(health.rejectedEvents, 1)
        XCTAssertEqual(health.droppedEvents, 1)
    }

    func testHubPropagatesOperationIdentityAndMergesCoreRedactionHealth() async throws {
        let fixture = try makeObservabilityFixture()
        defer { fixture.cleanup() }
        let hub = ObservabilityHub(
            configurationStore: ObservabilityConfigurationStore(defaults: fixture.defaults),
            rootURL: fixture.logsURL,
            sessionID: "identity-session",
            expectedCoreBuildContext: observabilityTestCoreBuildContext()
        )
        await hub.configure(configuration(mode: .disabled, minimumSeverity: .trace))

        var semanticEvent = ObservabilitySemanticEventInput(
            actionID: "repository.import.retry.confirmed",
            componentID: "macos.import.progress"
        )
        semanticEvent.traceID = "trace-id"
        semanticEvent.operationID = "operation-id"
        semanticEvent.retryOfOperationID = "previous-operation-id"
        await hub.recordSemanticAction(semanticEvent)
        let recentEvents = await hub.recentEvents(limit: 1)
        let event = try XCTUnwrap(recentEvents.first)
        XCTAssertEqual(event.traceID, "trace-id")
        XCTAssertEqual(event.operationID, "operation-id")
        XCTAssertEqual(event.retryOfOperationID, "previous-operation-id")

        let coreHealth = CoreObservabilityHealthSnapshot(
            initialized: true,
            mode: .disabled,
            queueDepth: 0,
            queueCapacity: 64,
            droppedTrace: 0,
            droppedDebug: 0,
            droppedInfo: 1,
            droppedWarn: 0,
            droppedError: 0,
            redactionRejected: 2,
            callbackConnected: true,
            degraded: false,
            degradedReason: nil
        )
        let health = await hub.health(core: coreHealth)
        XCTAssertEqual(health.rejectedEvents, 2)
        XCTAssertEqual(health.coreRedactionRejectedEvents, 2)
        XCTAssertEqual(health.droppedEvents, 1)
    }

    func testAppLoggerProjectsUIOperationAndRetryIdentity() async throws {
        let fixture = try makeObservabilityFixture()
        defer { fixture.cleanup() }
        let hub = ObservabilityHub(
            configurationStore: ObservabilityConfigurationStore(defaults: fixture.defaults),
            rootURL: fixture.logsURL,
            sessionID: "app-logger-session",
            expectedCoreBuildContext: observabilityTestCoreBuildContext()
        )
        await hub.configure(configuration(mode: .disabled, minimumSeverity: .trace))
        let logger = AppLogger(hub: hub)

        await logger.recordUIAction(
            actionID: "repository.import.retry.confirmed",
            context: AppUIActionContext(
                traceID: "trace-id",
                operationID: "operation-id",
                retryOfOperationID: "previous-operation-id",
                componentID: "macos.import.progress"
            )
        )
        await logger.recordUIAction(
            actionID: "app.command.settings.triggered",
            context: AppUIActionContext(traceID: "default-operation-trace")
        )

        let events = await hub.recentEvents(limit: 2)
        let retryEvent = try XCTUnwrap(events.first { $0.actionID == "repository.import.retry.confirmed" })
        XCTAssertEqual(retryEvent.traceID, "trace-id")
        XCTAssertEqual(retryEvent.operationID, "operation-id")
        XCTAssertEqual(retryEvent.retryOfOperationID, "previous-operation-id")
        let defaultEvent = try XCTUnwrap(events.first { $0.actionID == "app.command.settings.triggered" })
        XCTAssertFalse(try XCTUnwrap(defaultEvent.operationID).isEmpty)
        XCTAssertNil(defaultEvent.retryOfOperationID)
    }

    func testIncidentFreezesFiveMinutesBeforeAndThirtySecondsAfterMark() async throws {
        let fixture = try makeObservabilityFixture()
        defer { fixture.cleanup() }
        let clock = TestObservabilityClock(milliseconds: 1_000_000)
        let hub = ObservabilityHub(
            configurationStore: ObservabilityConfigurationStore(defaults: fixture.defaults),
            rootURL: fixture.logsURL,
            sessionID: "incident-session",
            expectedCoreBuildContext: observabilityTestCoreBuildContext(),
            now: { clock.date },
            idGenerator: { "incident-window" }
        )
        await hub.configure(configuration(mode: .disabled, minimumSeverity: .trace))
        await hub.ingestCoreEvent(event(id: "too-old", timestamp: 699_999, sessionID: "incident-session"))
        await hub.ingestCoreEvent(event(id: "lower-bound", timestamp: 700_000, sessionID: "incident-session"))
        await hub.ingestCoreEvent(event(id: "marked", timestamp: 1_000_000, sessionID: "incident-session"))

        let incidentID = await hub.markIncident(note: "token=must-not-persist")
        let activeIncidentID = await hub.activeIncidentID()
        XCTAssertEqual(incidentID, "incident-window")
        XCTAssertEqual(activeIncidentID, incidentID)

        clock.milliseconds = 1_030_000
        await hub.ingestCoreEvent(event(id: "upper-bound", timestamp: 1_030_000, sessionID: "incident-session"))
        clock.milliseconds = 1_030_001
        await hub.ingestCoreEvent(event(id: "after-window", timestamp: 1_030_001, sessionID: "incident-session"))

        var snapshots = await hub.incidentSnapshots()
        var snapshot = try XCTUnwrap(snapshots.first)
        XCTAssertEqual(snapshot.events.map(\.eventID), ["lower-bound", "marked", "upper-bound"])
        XCTAssertEqual(snapshot.note, "[REDACTED]")
        XCTAssertTrue(snapshot.isFrozen)
        let expiredIncidentID = await hub.activeIncidentID()
        XCTAssertNil(expiredIncidentID)
        try await hub.updateIncident(id: incidentID, status: "resolved")
        snapshots = await hub.incidentSnapshots()
        snapshot = try XCTUnwrap(snapshots.first)
        XCTAssertEqual(snapshot.status, .resolved)
    }

    func testHubRedactsSensitiveFieldsAndRejectsProhibitedEvents() async throws {
        let fixture = try makeObservabilityFixture()
        defer { fixture.cleanup() }
        let hub = ObservabilityHub(
            configurationStore: ObservabilityConfigurationStore(defaults: fixture.defaults),
            rootURL: fixture.logsURL,
            sessionID: "privacy-session",
            expectedCoreBuildContext: observabilityTestCoreBuildContext()
        )
        let config = configuration(mode: .developer, minimumSeverity: .trace)
        await hub.configure(config)
        await hub.ingestCoreEvent(event(
            id: "prohibited",
            timestamp: 1,
            sessionID: "privacy-session",
            privacy: "prohibited"
        ))
        var sensitive = event(
            id: "sensitive",
            timestamp: 2,
            sessionID: "privacy-session",
            message: "private filename",
            privacy: "sensitive"
        )
        sensitive.attributes = [
            ObservabilityAttributeSnapshot(key: "path", value: "/private/path", privacy: "sensitive")
        ]
        sensitive.error = ObservabilityErrorSnapshot(code: "E_TEST", technicalDetails: "raw detail")
        await hub.ingestCoreEvent(sensitive)
        try await hub.flush()

        let stored = try RollingObservabilityStore(rootURL: fixture.logsURL).loadRecentEvents(limit: 10)
        XCTAssertEqual(stored.map(\.eventID), ["sensitive"])
        XCTAssertEqual(stored.first?.message, "[REDACTED]")
        XCTAssertEqual(stored.first?.attributes.first?.value, "[REDACTED]")
        XCTAssertEqual(stored.first?.error?.technicalDetails, "[REDACTED]")
        let health = await hub.health(core: nil)
        XCTAssertEqual(health.rejectedEvents, 1)
    }
}

extension ObservabilityHubAndStoreTests {
    func testHubRejectsUnsafeWireValuesBeforeMemoryAndDiskSinks() async throws {
        let fixture = try makeObservabilityFixture()
        defer { fixture.cleanup() }
        let hub = ObservabilityHub(
            configurationStore: ObservabilityConfigurationStore(defaults: fixture.defaults),
            rootURL: fixture.logsURL,
            sessionID: "wire-safety-session",
            expectedCoreBuildContext: observabilityTestCoreBuildContext()
        )
        await hub.configure(configuration(mode: .developer, minimumSeverity: .trace))

        for rejected in unsafeWireEvents(sessionID: "wire-safety-session") {
            await hub.ingestCoreEvent(rejected)
        }

        let sanitized = sanitizedWireEvent(sessionID: "wire-safety-session")
        await hub.ingestCoreEvent(sanitized)
        try await hub.flush()

        let memory = await hub.recentEvents(limit: 10)
        let stored = try RollingObservabilityStore(rootURL: fixture.logsURL).loadRecentEvents(limit: 10)
        XCTAssertEqual(memory.map(\.eventID), ["sanitized"])
        XCTAssertEqual(stored.map(\.eventID), ["sanitized"])
        for accepted in try [XCTUnwrap(memory.first), XCTUnwrap(stored.first)] {
            XCTAssertEqual(accepted.message, "[REDACTED]")
            XCTAssertNil(accepted.target)
            XCTAssertNil(accepted.threadName)
        }
        let health = await hub.health(core: nil)
        XCTAssertEqual(health.rejectedEvents, 5)
    }

    func testHubPreservesBenignFreeTextAndAbsentFields() async throws {
        let fixture = try makeObservabilityFixture()
        defer { fixture.cleanup() }
        let hub = ObservabilityHub(
            configurationStore: ObservabilityConfigurationStore(defaults: fixture.defaults),
            rootURL: fixture.logsURL,
            sessionID: "benign-text-session",
            expectedCoreBuildContext: observabilityTestCoreBuildContext()
        )
        await hub.configure(configuration(mode: .developer, minimumSeverity: .trace))
        var benign = event(id: "benign", timestamp: 1, sessionID: "benign-text-session")
        benign.message = "operation completed"
        benign.target = "area_matrix_core"
        benign.threadName = "worker-main"

        await hub.ingestCoreEvent(benign)
        await hub.ingestCoreEvent(event(id: "absent", timestamp: 2, sessionID: "benign-text-session"))
        try await hub.flush()

        let memory = await hub.recentEvents(limit: 10)
        let stored = try RollingObservabilityStore(rootURL: fixture.logsURL).loadRecentEvents(limit: 10)
        for snapshots in [memory, stored] {
            XCTAssertEqual(snapshots.map(\.eventID), ["benign", "absent"])
            XCTAssertEqual(snapshots.first?.message, "operation completed")
            XCTAssertEqual(snapshots.first?.target, "area_matrix_core")
            XCTAssertEqual(snapshots.first?.threadName, "worker-main")
            XCTAssertNil(snapshots.last?.message)
            XCTAssertNil(snapshots.last?.target)
            XCTAssertNil(snapshots.last?.threadName)
        }
        let health = await hub.health(core: nil)
        XCTAssertEqual(health.rejectedEvents, 0)
    }

    func testHubRejectsUnpinnedAndMismatchedLiveCoreIdentity() async throws {
        let fixture = try makeObservabilityFixture()
        defer { fixture.cleanup() }
        let expected = observabilityTestCoreBuildContext()
        let hub = ObservabilityHub(
            configurationStore: ObservabilityConfigurationStore(defaults: fixture.defaults),
            rootURL: fixture.logsURL,
            sessionID: "core-identity-session"
        )
        await hub.configure(configuration(mode: .disabled, minimumSeverity: .trace))
        await hub.ingestCoreEvent(event(id: "unpinned", timestamp: 1, sessionID: "core-identity-session"))
        let didPinBuildContext = await hub.configureCoreBuildContext(expected)
        XCTAssertTrue(didPinBuildContext)
        await hub.ingestCoreEvent(event(id: "accepted", timestamp: 2, sessionID: "core-identity-session"))

        var mismatches = [ObservabilityBuildContextSnapshot]()
        var candidate = expected
        candidate.producer = "areamatrix_macos"
        mismatches.append(candidate)
        candidate = expected
        candidate.version = "0.2.0"
        mismatches.append(candidate)
        candidate = expected
        candidate.build = "other"
        mismatches.append(candidate)
        candidate = expected
        candidate.configuration = "release"
        mismatches.append(candidate)
        candidate = expected
        candidate.architecture = "x86_64"
        mismatches.append(candidate)
        candidate = expected
        candidate.platform = "linux"
        mismatches.append(candidate)
        for (index, buildContext) in mismatches.enumerated() {
            var rejected = event(
                id: "mismatch-\(index)",
                timestamp: Int64(index + 3),
                sessionID: "core-identity-session"
            )
            rejected.buildContext = buildContext
            await hub.ingestCoreEvent(rejected)
        }

        let acceptedEventIDs = await hub.recentEvents(limit: 10).map(\.eventID)
        let health = await hub.health(core: nil)
        XCTAssertEqual(acceptedEventIDs, ["accepted"])
        XCTAssertEqual(health.rejectedEvents, UInt64(mismatches.count + 1))
    }

    func testWriterFailureDegradesWithoutTouchingSiblingFiles() async throws {
        let fixture = try makeObservabilityFixture()
        defer { fixture.cleanup() }
        let siblingURL = fixture.rootURL.appendingPathComponent("README.md")
        try Data("user content".utf8).write(to: siblingURL)
        try Data("not a directory".utf8).write(to: fixture.logsURL)
        let hub = ObservabilityHub(
            configurationStore: ObservabilityConfigurationStore(defaults: fixture.defaults),
            rootURL: fixture.logsURL,
            sessionID: "degraded-session",
            expectedCoreBuildContext: observabilityTestCoreBuildContext()
        )
        await hub.configure(configuration(mode: .developer))
        await hub.recordSemanticAction(ObservabilitySemanticEventInput(
            actionID: "diagnostics.export.confirmed",
            componentID: "macos.observability.runtime"
        ))

        let health = await hub.health(core: nil)
        XCTAssertFalse(health.writerAvailable)
        XCTAssertEqual(health.degradedReason, "writer-unavailable")
        XCTAssertEqual(health.memoryEventCount, 1)
        XCTAssertEqual(try String(contentsOf: siblingURL, encoding: .utf8), "user content")
    }

    func testLateSemanticEventCannotReopenStoreAfterShutdown() async throws {
        let fixture = try makeObservabilityFixture()
        defer { fixture.cleanup() }
        let hub = ObservabilityHub(
            configurationStore: ObservabilityConfigurationStore(defaults: fixture.defaults),
            rootURL: fixture.logsURL,
            sessionID: "shutdown-session",
            expectedCoreBuildContext: observabilityTestCoreBuildContext()
        )
        await hub.configure(configuration(mode: .developer, minimumSeverity: .trace))
        await hub.recordSemanticAction(ObservabilitySemanticEventInput(
            actionID: "diagnostics.export.confirmed",
            componentID: "macos.observability.runtime"
        ))
        try await hub.flush()
        try await hub.shutdown()

        let filesBeforeLateEvent = try observabilityEventURLs(in: fixture.logsURL)
        let eventsBeforeLateEvent = await hub.recentEvents(limit: 100)
        await hub.recordSemanticAction(ObservabilitySemanticEventInput(
            actionID: "diagnostics.export.confirmed",
            componentID: "macos.observability.runtime"
        ))
        let eventsAfterLateEvent = await hub.recentEvents(limit: 100)

        XCTAssertEqual(try observabilityEventURLs(in: fixture.logsURL), filesBeforeLateEvent)
        XCTAssertEqual(eventsAfterLateEvent, eventsBeforeLateEvent)
    }
}

private extension ObservabilityHubAndStoreTests {
    func unsafeWireEvents(sessionID: String) -> [ObservabilityEventSnapshot] {
        var credential = event(id: "credential", timestamp: 1, sessionID: sessionID)
        credential.message = "accessToken opaque"
        var confusableKey = event(id: "confusable-key", timestamp: 2, sessionID: sessionID, privacy: "sensitive")
        confusableKey.attributes = [
            .init(key: "accessＴoken", value: "opaque", privacy: "sensitive")
        ]
        var underclassified = event(id: "locator", timestamp: 3, sessionID: sessionID)
        underclassified.message = "/Users/example/private.txt"
        var invalidResource = event(id: "resource", timestamp: 4, sessionID: sessionID, privacy: "pseudonymous")
        invalidResource.resources = [
            .init(
                resourceID: "00000000-0000-4000-8000-000000000001",
                alias: "file.0123456789ABCDEF01234567",
                pathExtension: "txt",
                sizeBucket: "lt_1mb",
                storageMode: "copied"
            )
        ]
        var invalidBuild = event(id: "build", timestamp: 5, sessionID: sessionID)
        invalidBuild.buildContext = .init(
            producer: "area_matrix_core",
            version: "0.1.0",
            build: "test",
            configuration: "debug",
            platform: "macos",
            architecture: "arm64"
        )
        return [credential, confusableKey, underclassified, invalidResource, invalidBuild]
    }

    func sanitizedWireEvent(sessionID: String) -> ObservabilityEventSnapshot {
        var sanitized = event(id: "sanitized", timestamp: 6, sessionID: sessionID, privacy: "sensitive")
        sanitized.message = "来源，/用户/机密.txt"
        sanitized.target = "file:///Users/example/private.txt"
        sanitized.threadName = "worker /Users/example/private.txt"
        return sanitized
    }
}
