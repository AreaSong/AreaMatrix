@testable import AreaMatrix
import XCTest

final class DatabaseRepairConfirmPageFeatureTests: XCTestCase {
    @MainActor
    func testS137C116StartupRecoveryRunsRealCoreBridgeBoundaryBeforeRepair() async {
        let report = RecoveryReportSnapshot(
            cleanedStagingFiles: 2,
            revertedStagingDbRows: 1,
            warnings: ["Kept recoverable staging file"]
        )
        let recoverer = S137RecordingStartupRecoverer(result: .success(report))
        let repairer = S137RecordingMetadataRepairer(result: .success(.s137RepairReportFixture()))
        let model = DatabaseRepairConfirmModel(
            repoPath: "/tmp/repo",
            scanSession: nil,
            mapping: nil,
            lastOpenedAt: nil,
            metadataRepairer: repairer,
            startupRecoverer: recoverer,
            diagnosticsCollector: ShellRecordingDiagnosticsCollector(result: .success(.s137DiagnosticsFixture())),
            errorMapper: S137RepairErrorMapper(mapping: .s137RepairMapping(kind: .db))
        )

        await model.runStartupRecoveryCheckIfNeeded()
        let recoveryRequests = await recoverer.requestedRepoPaths()
        let repairRequests = await repairer.requests()

        XCTAssertEqual(recoveryRequests, ["/tmp/repo"])
        XCTAssertEqual(model.startupRecoveryState, .completed(report))
        XCTAssertEqual(repairRequests, [])
    }

    @MainActor
    func testS137C116StartupRecoveryFailureMapsErrorAndCanRetry() async {
        let mapping = CoreErrorMappingSnapshot.s137StartupRecoveryMapping(rawContext: "database locked")
        let recoverer = S137RecordingStartupRecoverer(results: [
            .failure(CoreError.Db(message: "database locked")),
            .success(RecoveryReportSnapshot(cleanedStagingFiles: 0, revertedStagingDbRows: 0, warnings: []))
        ])
        let model = DatabaseRepairConfirmModel(
            repoPath: "/tmp/repo",
            scanSession: nil,
            mapping: nil,
            lastOpenedAt: nil,
            metadataRepairer: S137RecordingMetadataRepairer(result: .success(.s137RepairReportFixture())),
            startupRecoverer: recoverer,
            diagnosticsCollector: ShellRecordingDiagnosticsCollector(result: .success(.s137DiagnosticsFixture())),
            errorMapper: S137RepairErrorMapper(mapping: mapping)
        )

        await model.runStartupRecoveryCheckIfNeeded()
        XCTAssertEqual(model.startupRecoveryState, .failed(mapping))

        await model.runStartupRecoveryCheckIfNeeded()
        var recoveryRequests = await recoverer.requestedRepoPaths()
        XCTAssertEqual(recoveryRequests, ["/tmp/repo"])

        await model.retryStartupRecovery()
        recoveryRequests = await recoverer.requestedRepoPaths()
        XCTAssertEqual(recoveryRequests, ["/tmp/repo", "/tmp/repo"])
        XCTAssertEqual(model.startupRecoveryState, .completed(nil))
    }

    @MainActor
    func testS137C126RepairRequiresConfirmationAndUsesCoreMetadataRepair() async {
        let report = RepairReportSnapshot(
            scanSessionId: 9,
            diagnosticsSnapshotPath: ".areamatrix/diagnostics/repair.zip",
            inserted: 3,
            updated: 2,
            skipped: 1,
            errors: []
        )
        let repairer = S137RecordingMetadataRepairer(result: .success(report))
        let model = DatabaseRepairConfirmModel(
            repoPath: "/tmp/repo",
            scanSession: nil,
            mapping: nil,
            lastOpenedAt: nil,
            metadataRepairer: repairer,
            diagnosticsCollector: ShellRecordingDiagnosticsCollector(result: .success(.s137DiagnosticsFixture())),
            errorMapper: S137RepairErrorMapper(mapping: .s137RepairMapping(kind: .db))
        )

        await model.runFullRescan()
        let requestsBeforeConfirmation = await repairer.requests()
        XCTAssertEqual(requestsBeforeConfirmation, [])
        XCTAssertEqual(model.repairState, .idle)

        model.isMetadataSafetyConfirmed = true
        await model.runFullRescan()

        let requestsAfterConfirmation = await repairer.requests()
        XCTAssertEqual(requestsAfterConfirmation, [
            S137RepairRequest(
                repoPath: "/tmp/repo",
                options: RepairOptionsSnapshot(fullRescan: true, preserveDiagnosticsSnapshot: true)
            )
        ])
        XCTAssertEqual(model.repairState, .succeeded(report))
    }

    @MainActor
    func testS137C126RepairFailureMapsCoreErrorAndStaysRetryable() async {
        let mapping = CoreErrorMappingSnapshot.s137RepairMapping(
            kind: .permissionDenied,
            rawContext: "/tmp/repo/.areamatrix/index.db"
        )
        let repairer = S137RecordingMetadataRepairer(result: .failure(CoreError.PermissionDenied(
            path: "/tmp/repo/.areamatrix/index.db"
        )))
        let model = DatabaseRepairConfirmModel(
            repoPath: "/tmp/repo",
            scanSession: nil,
            mapping: nil,
            lastOpenedAt: nil,
            metadataRepairer: repairer,
            diagnosticsCollector: ShellRecordingDiagnosticsCollector(result: .success(.s137DiagnosticsFixture())),
            errorMapper: S137RepairErrorMapper(mapping: mapping)
        )

        model.isMetadataSafetyConfirmed = true
        await model.runFullRescan()

        XCTAssertEqual(model.repairState, .failed(mapping))
        XCTAssertEqual(model.primaryButtonTitle, "Retry Full Rescan")
        XCTAssertTrue(model.canRunFullRescan)
    }

    @MainActor
    func testS137C126DiagnosticsRequirePrivacyConfirmationAndCanDisableRepair() async {
        let diagnosticsCollector = ShellRecordingDiagnosticsCollector(
            result: .failure(CoreError.PermissionDenied(path: "/tmp/repo/.areamatrix/diagnostics"))
        )
        let model = DatabaseRepairConfirmModel(
            repoPath: "/tmp/repo",
            scanSession: nil,
            mapping: nil,
            lastOpenedAt: nil,
            metadataRepairer: S137RecordingMetadataRepairer(result: .success(.s137RepairReportFixture())),
            diagnosticsCollector: diagnosticsCollector,
            errorMapper: S137RepairErrorMapper(mapping: .s137RepairMapping(kind: .permissionDenied))
        )

        model.isMetadataSafetyConfirmed = true
        await model.collectDiagnostics()
        let requestsBeforeConfirmation = await diagnosticsCollector.requestedRepoPaths()
        XCTAssertEqual(requestsBeforeConfirmation, [])
        XCTAssertTrue(model.canRunFullRescan)

        model.requestDiagnosticsExport()
        await model.collectDiagnostics()

        let requestsAfterConfirmation = await diagnosticsCollector.requestedRepoPaths()
        XCTAssertEqual(requestsAfterConfirmation, ["/tmp/repo"])
        guard case let .failed(mapping) = model.diagnosticsState else {
            return XCTFail("expected diagnostics failure")
        }
        XCTAssertEqual(mapping.kind, .permissionDenied)
        XCTAssertFalse(model.canRunFullRescan)
    }

    @MainActor
    func testS137C126ViewExposesRepairCopyAndNoAdjacentCoreActionsWhenNoScanSession() {
        let view = DBRepairConfirmView(
            repoPath: "/tmp/repo",
            scanSession: nil,
            mapping: .s137RepairMapping(kind: .db, rawContext: "database corrupted"),
            metadataRepairer: S137RecordingMetadataRepairer(result: .success(.s137RepairReportFixture())),
            diagnosticsCollector: ShellRecordingDiagnosticsCollector(result: .success(.s137DiagnosticsFixture())),
            errorMapper: S137RepairErrorMapper(mapping: .s137RepairMapping(kind: .db)),
            onCancel: {},
            onRepairSucceeded: {},
            onOpenRepositoryInFinder: {}
        )
        let body = s137MirrorDescription(of: view.body)

        XCTAssertTrue(body.contains("Repair Repository Metadata?"))
        XCTAssertTrue(body.contains("AreaMatrix cannot read the repository metadata database"))
        XCTAssertTrue(body.contains("Run Full Rescan"))
        XCTAssertTrue(body.contains("Export diagnostics..."))
        XCTAssertTrue(body.contains("S1-37-C1-26-run-full-rescan"))
        XCTAssertTrue(body.contains("S1-37-C1-26-confirm-metadata-only"))
        XCTAssertFalse(body.contains("Resume"))
        XCTAssertFalse(body.contains("Clean up and retry"))
        XCTAssertFalse(body.contains("Remove from index"))
    }

    @MainActor
    func testS137C116StartupRecoveryViewShowsReportAndRetryWithoutAdjacentActions() {
        let checkingView = StartupRecoveryCheckStatusView(
            state: .checking,
            onRetry: {}
        )
        let completedView = StartupRecoveryCheckStatusView(
            state: .completed(RecoveryReportSnapshot(
                cleanedStagingFiles: 1,
                revertedStagingDbRows: 2,
                warnings: ["Kept active staging file"]
            )),
            onRetry: {}
        )
        let failedView = StartupRecoveryCheckStatusView(
            state: .failed(.s137StartupRecoveryMapping(rawContext: "locked")),
            onRetry: {}
        )

        let checkingBody = s137MirrorDescription(of: checkingView.body)
        let completedBody = s137MirrorDescription(of: completedView.body)
        let failedBody = s137MirrorDescription(of: failedView.body)

        XCTAssertTrue(checkingBody.contains("Checking startup recovery state..."))
        XCTAssertTrue(checkingBody.contains("S1-37-C1-16-startup-recovery-checking"))
        XCTAssertTrue(completedBody.contains("Startup recovery checked"))
        XCTAssertTrue(completedBody.contains("Kept active staging file"))
        XCTAssertTrue(completedBody.contains("S1-37-C1-16-startup-recovery-completed"))
        XCTAssertTrue(failedBody.contains("Startup recovery failed"))
        XCTAssertTrue(failedBody.contains("Retry startup recovery"))
        XCTAssertTrue(failedBody.contains("S1-37-C1-16-retry-startup-recovery"))
        XCTAssertFalse(completedBody.contains("Remove from index"))
        XCTAssertFalse(failedBody.contains("Download & retry"))
    }

    @MainActor
    func testS137C126ViewDoesNotExposeAdjacentCoreActionsWhenScanSessionExists() {
        let view = DBRepairConfirmView(
            repoPath: "/tmp/repo",
            scanSession: ScanSessionSnapshot.mainLoadingReindexFixture(status: .interrupted),
            mapping: .s137RepairMapping(kind: .db, rawContext: "database corrupted"),
            metadataRepairer: S137RecordingMetadataRepairer(result: .success(.s137RepairReportFixture())),
            diagnosticsCollector: ShellRecordingDiagnosticsCollector(result: .success(.s137DiagnosticsFixture())),
            errorMapper: S137RepairErrorMapper(mapping: .s137RepairMapping(kind: .db)),
            onCancel: {},
            onRepairSucceeded: {},
            onOpenRepositoryInFinder: {}
        )
        let body = s137MirrorDescription(of: view.body)

        XCTAssertTrue(body.contains("Run Full Rescan"))
        XCTAssertTrue(body.contains("Export diagnostics..."))
        XCTAssertFalse(body.contains("Resume"))
        XCTAssertFalse(body.contains("Clean up and retry"))
        XCTAssertFalse(body.contains("Interrupted scan"))
    }

    func testS137C126CoreBridgeDeclaresRepairMetadataBoundary() async {
        let declaredBoundaries = await CoreBridge().declaredBoundaries()

        XCTAssertTrue(CoreBridgeBoundary.allCases.contains(.repairMetadata))
        XCTAssertTrue(declaredBoundaries.contains(.repairMetadata))
    }

    func testS137C116CoreBridgeDeclaresStartupRecoveryBoundary() async {
        let declaredBoundaries = await CoreBridge().declaredBoundaries()

        XCTAssertTrue(CoreBridgeBoundary.allCases.contains(.recoverOnStartup))
        XCTAssertTrue(declaredBoundaries.contains(.recoverOnStartup))
    }
}

struct S137RepairRequest: Equatable {
    var repoPath: String
    var options: RepairOptionsSnapshot
}

actor S137RecordingMetadataRepairer: CoreMetadataRepairing {
    private let result: Result<RepairReportSnapshot, Error>
    private var recordedRequests: [S137RepairRequest] = []

    init(result: Result<RepairReportSnapshot, Error>) {
        self.result = result
    }

    func repairMetadata(repoPath: String, options: RepairOptionsSnapshot) async throws -> RepairReportSnapshot {
        recordedRequests.append(S137RepairRequest(repoPath: repoPath, options: options))
        return try result.get()
    }

    func requests() -> [S137RepairRequest] {
        recordedRequests
    }
}

private enum S137StartupRecoveryResult {
    case success(RecoveryReportSnapshot)
    case failure(Error)
}

private actor S137RecordingStartupRecoverer: CoreStartupRecovering {
    private var results: [S137StartupRecoveryResult]
    private var repoPaths: [String] = []

    init(result: S137StartupRecoveryResult) {
        results = [result]
    }

    init(results: [S137StartupRecoveryResult]) {
        self.results = results
    }

    func recoverOnStartup(repoPath: String) async throws -> RecoveryReportSnapshot {
        repoPaths.append(repoPath)
        let result = results.isEmpty ? .success(RecoveryReportSnapshot(
            cleanedStagingFiles: 0,
            revertedStagingDbRows: 0,
            warnings: []
        )) : results.removeFirst()
        switch result {
        case let .success(report):
            return report
        case let .failure(error):
            throw error
        }
    }

    func requestedRepoPaths() -> [String] {
        repoPaths
    }
}

private actor S137RepairErrorMapper: CoreErrorMapping {
    private let mapping: CoreErrorMappingSnapshot

    init(mapping: CoreErrorMappingSnapshot) {
        self.mapping = mapping
    }

    func mapCoreError(_: CoreError) async -> CoreErrorMappingSnapshot {
        mapping
    }
}

private extension RepairReportSnapshot {
    static func s137RepairReportFixture() -> RepairReportSnapshot {
        RepairReportSnapshot(
            scanSessionId: 7,
            diagnosticsSnapshotPath: ".areamatrix/diagnostics/repair.zip",
            inserted: 1,
            updated: 2,
            skipped: 3,
            errors: []
        )
    }
}

private extension DiagnosticsSnapshotSnapshot {
    static func s137DiagnosticsFixture() -> DiagnosticsSnapshotSnapshot {
        DiagnosticsSnapshotSnapshot(
            snapshotPath: ".areamatrix/diagnostics/s1-37.zip",
            createdAt: 1_778_000_000,
            warnings: ["paths redacted"]
        )
    }
}

private extension CoreErrorMappingSnapshot {
    static func s137RepairMapping(
        kind: CoreErrorKindSnapshot,
        rawContext: String = "db corrupt"
    ) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: kind,
            userMessage: "Repository metadata needs repair",
            severity: .critical,
            suggestedAction: "Run a full metadata rescan after preserving diagnostics.",
            recoverability: .userActionRequired,
            rawContext: rawContext
        )
    }

    static func s137StartupRecoveryMapping(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "Startup recovery could not finish",
            severity: .medium,
            suggestedAction: "Retry startup recovery before running metadata repair.",
            recoverability: .retryable,
            rawContext: rawContext
        )
    }
}

private func s137MirrorDescription(of value: Any) -> String {
    var lines: [String] = []
    appendS137MirrorDescription(of: value, to: &lines)
    return lines.joined(separator: "\n")
}

private func appendS137MirrorDescription(of value: Any, to lines: inout [String]) {
    lines.append(String(describing: type(of: value)))
    lines.append(String(describing: value))
    for child in Mirror(reflecting: value).children {
        if let label = child.label {
            lines.append(label)
        }
        appendS137MirrorDescription(of: child.value, to: &lines)
    }
}
