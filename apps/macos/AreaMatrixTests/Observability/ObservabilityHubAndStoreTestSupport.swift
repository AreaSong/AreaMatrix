@testable import AreaMatrix
import XCTest

struct ObservabilityTestFixture {
    var rootURL: URL
    var logsURL: URL
    var defaults: UserDefaults
    var suiteName: String

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
        removeTestTemporaryItems(rootURL)
    }
}

func makeObservabilityFixture() throws -> ObservabilityTestFixture {
    let rootURL = try makeTestTemporaryDirectory(named: "AreaMatrixObservability")
    let suiteName = "AreaMatrixObservabilityTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return ObservabilityTestFixture(
        rootURL: rootURL,
        logsURL: rootURL.appendingPathComponent("Logs", isDirectory: true),
        defaults: defaults,
        suiteName: suiteName
    )
}

func configuration(
    mode: AppObservabilityMode,
    minimumSeverity: AppObservabilitySeverity = .info,
    diskBudgetBytes: Int64 = 100 * 1024 * 1024,
    retentionHours: Int = 24
) -> AppObservabilityConfiguration {
    AppObservabilityConfiguration(
        mode: mode,
        minimumSeverity: minimumSeverity,
        diskBudgetBytes: diskBudgetBytes,
        retentionHours: retentionHours,
        includeSensitive: false
    )
}

func observabilityTestCoreBuildContext() -> ObservabilityBuildContextSnapshot {
    ObservabilityBuildContextSnapshot(
        producer: "area_matrix_core",
        version: "0.1.0",
        build: "test",
        configuration: "debug",
        platform: "macos",
        architecture: "aarch64"
    )
}

func event(
    id: String,
    timestamp: Int64,
    sessionID: String,
    message: String? = nil,
    privacy: String = "public"
) -> ObservabilityEventSnapshot {
    ObservabilityEventSnapshot(
        schemaVersion: 2,
        eventID: id,
        wallTimestampMilliseconds: timestamp,
        monotonicTimestampNanoseconds: UInt64(max(0, timestamp)),
        sequenceNumber: UInt64(max(0, timestamp)),
        sessionID: sessionID,
        incidentID: nil,
        traceID: "trace-\(id)",
        spanID: "span-\(id)",
        parentSpanID: nil,
        operationID: nil,
        retryOfOperationID: nil,
        actionID: "diagnostics.export.confirmed",
        componentID: "macos.observability.runtime",
        layer: "platform",
        phase: "event",
        severity: .info,
        outcome: "succeeded",
        durationMilliseconds: nil,
        resources: [],
        error: nil,
        attributes: [],
        privacy: privacy,
        message: message,
        target: nil,
        threadName: nil,
        buildContext: observabilityTestCoreBuildContext()
    )
}

func incident(id: String, sessionID: String) -> ObservabilityIncidentSnapshot {
    ObservabilityIncidentSnapshot(
        id: id,
        sessionID: sessionID,
        markedAtMilliseconds: 1,
        captureEndsAtMilliseconds: 2,
        status: .open,
        note: nil,
        events: [],
        isFrozen: false,
        recoveredAfterRestart: false
    )
}

func observabilityEventURLs(in rootURL: URL) throws -> [URL] {
    try FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)
        .filter { $0.lastPathComponent.hasPrefix("events-") && $0.pathExtension == "jsonl" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
}

func observabilityPermissions(at url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
}
