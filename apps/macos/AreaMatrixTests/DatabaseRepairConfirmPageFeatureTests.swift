@testable import AreaMatrix
import XCTest

final class DatabaseRepairConfirmPageFeatureTests: XCTestCase {
    @MainActor
    func testDatabaseRepairStartupRecoveryCoreStartupRecoveryRunsRealCoreBridgeBoundaryBeforeRepair() async {
        let report = RecoveryReportSnapshot(
            cleanedStagingFiles: 2,
            revertedStagingDbRows: 1,
            warnings: ["Kept recoverable staging file"]
        )
        let recoverer = DatabaseRepairRecordingStartupRecoverer(result: .success(report))
        let repairer = DatabaseRepairRecordingMetadataRepairer(result: .success(.databaseRepairRepairReportFixture()))
        let model = DatabaseRepairConfirmModel(
            repoPath: "/tmp/repo",
            scanSession: nil,
            mapping: nil,
            lastOpenedAt: nil,
            metadataRepairer: repairer,
            startupRecoverer: recoverer,
            diagnosticsCollector: ShellRecordingDiagnosticsCollector(
                result: .success(.databaseRepairDiagnosticsFixture())
            ),
            errorMapper: DatabaseRepairRepairErrorMapper(mapping: .databaseRepairRepairMapping(kind: .db))
        )

        await model.runStartupRecoveryCheckIfNeeded()
        let recoveryRequests = await recoverer.requestedRepoPaths()
        let repairRequests = await repairer.requests()

        XCTAssertEqual(recoveryRequests, ["/tmp/repo"])
        XCTAssertEqual(model.startupRecoveryState, .completed(report))
        XCTAssertEqual(repairRequests, [])
    }

    @MainActor
    func testDatabaseRepairStartupRecoveryCoreStartupRecoveryFailureMapsErrorAndCanRetry() async {
        let mapping = CoreErrorMappingSnapshot.databaseRepairStartupRecoveryMapping(rawContext: "database locked")
        let recoverer = DatabaseRepairRecordingStartupRecoverer(results: [
            .failure(CoreError.Db(message: "database locked")),
            .success(RecoveryReportSnapshot(cleanedStagingFiles: 0, revertedStagingDbRows: 0, warnings: []))
        ])
        let model = DatabaseRepairConfirmModel(
            repoPath: "/tmp/repo",
            scanSession: nil,
            mapping: nil,
            lastOpenedAt: nil,
            metadataRepairer: DatabaseRepairRecordingMetadataRepairer(
                result: .success(.databaseRepairRepairReportFixture())
            ),
            startupRecoverer: recoverer,
            diagnosticsCollector: ShellRecordingDiagnosticsCollector(
                result: .success(.databaseRepairDiagnosticsFixture())
            ),
            errorMapper: DatabaseRepairRepairErrorMapper(mapping: mapping)
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
    func testDatabaseRepairRepairReindexMetadataCoreRepairRequiresConfirmationAndUsesCoreMetadataRepair() async {
        let report = RepairReportSnapshot(
            scanSessionId: 9,
            diagnosticsSnapshotPath: ".areamatrix/diagnostics/repair.zip",
            inserted: 3,
            updated: 2,
            skipped: 1,
            errors: []
        )
        let repairer = DatabaseRepairRecordingMetadataRepairer(result: .success(report))
        let model = DatabaseRepairConfirmModel(
            repoPath: "/tmp/repo",
            scanSession: nil,
            mapping: nil,
            lastOpenedAt: nil,
            metadataRepairer: repairer,
            diagnosticsCollector: ShellRecordingDiagnosticsCollector(
                result: .success(.databaseRepairDiagnosticsFixture())
            ),
            errorMapper: DatabaseRepairRepairErrorMapper(mapping: .databaseRepairRepairMapping(kind: .db))
        )

        await model.runFullRescan()
        let requestsBeforeConfirmation = await repairer.requests()
        XCTAssertEqual(requestsBeforeConfirmation, [])
        XCTAssertEqual(model.repairState, .idle)

        model.isMetadataSafetyConfirmed = true
        await model.runFullRescan()

        let requestsAfterConfirmation = await repairer.requests()
        XCTAssertEqual(requestsAfterConfirmation, [
            DatabaseRepairRepairRequest(
                repoPath: "/tmp/repo",
                options: RepairOptionsSnapshot(fullRescan: true, preserveDiagnosticsSnapshot: true)
            )
        ])
        XCTAssertEqual(model.repairState, .succeeded(report))
    }

    @MainActor
    func testDatabaseRepairRepairReindexMetadataCoreRepairFailureMapsCoreErrorAndStaysRetryable() async {
        let mapping = CoreErrorMappingSnapshot.databaseRepairRepairMapping(
            kind: .permissionDenied,
            rawContext: "/tmp/repo/.areamatrix/index.db"
        )
        let repairer = DatabaseRepairRecordingMetadataRepairer(result: .failure(CoreError.PermissionDenied(
            path: "/tmp/repo/.areamatrix/index.db"
        )))
        let model = DatabaseRepairConfirmModel(
            repoPath: "/tmp/repo",
            scanSession: nil,
            mapping: nil,
            lastOpenedAt: nil,
            metadataRepairer: repairer,
            diagnosticsCollector: ShellRecordingDiagnosticsCollector(
                result: .success(.databaseRepairDiagnosticsFixture())
            ),
            errorMapper: DatabaseRepairRepairErrorMapper(mapping: mapping)
        )

        model.isMetadataSafetyConfirmed = true
        await model.runFullRescan()

        XCTAssertEqual(model.repairState, .failed(mapping))
        XCTAssertEqual(model.primaryButtonTitle, "Retry Full Rescan")
        XCTAssertTrue(model.canRunFullRescan)
    }

    @MainActor
    func testDatabaseRepairRepairReindexMetadataCoreDiagnosticsRequirePrivacyConfirmationAndCanDisableRepair() async {
        let diagnosticsCollector = ShellRecordingDiagnosticsCollector(
            result: .failure(CoreError.PermissionDenied(path: "/tmp/repo/.areamatrix/diagnostics"))
        )
        let model = DatabaseRepairConfirmModel(
            repoPath: "/tmp/repo",
            scanSession: nil,
            mapping: nil,
            lastOpenedAt: nil,
            metadataRepairer: DatabaseRepairRecordingMetadataRepairer(
                result: .success(.databaseRepairRepairReportFixture())
            ),
            diagnosticsCollector: diagnosticsCollector,
            errorMapper: DatabaseRepairRepairErrorMapper(mapping: .databaseRepairRepairMapping(kind: .permissionDenied))
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
    func testDatabaseRepairRepairReindexMetadataCoreViewExposesRepairCopyAndNoAdjacentCoreActionsWhenNoScanSession() {
        let view = DBRepairConfirmView(
            repoPath: "/tmp/repo",
            scanSession: nil,
            mapping: .databaseRepairRepairMapping(kind: .db, rawContext: "database corrupted"),
            metadataRepairer: DatabaseRepairRecordingMetadataRepairer(
                result: .success(.databaseRepairRepairReportFixture())
            ),
            diagnosticsCollector: ShellRecordingDiagnosticsCollector(
                result: .success(.databaseRepairDiagnosticsFixture())
            ),
            errorMapper: DatabaseRepairRepairErrorMapper(mapping: .databaseRepairRepairMapping(kind: .db)),
            onCancel: {},
            onRepairSucceeded: {},
            onOpenRepositoryInFinder: {}
        )
        let body = testMirrorDescription(of: view.body)

        assertTestDescription(body, contains: [
            "Repair Repository Metadata?",
            "AreaMatrix cannot read the repository metadata database",
            "Run Full Rescan",
            "Export diagnostics...",
            "database-repair-metadata-repair-run-full-rescan",
            "database-repair-metadata-repair-confirm-metadata-only"
        ])
        assertTestDescription(body, doesNotContain: [
            "Resume",
            "Clean up and retry",
            "Remove from index"
        ])
    }

    @MainActor
    func testDatabaseRepairStartupRecoveryCoreStartupRecoveryViewShowsReportAndRetryWithoutAdjacentActions() {
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
            state: .failed(.databaseRepairStartupRecoveryMapping(rawContext: "locked")),
            onRetry: {}
        )

        let checkingBody = testMirrorDescription(of: checkingView.body)
        let completedBody = testMirrorDescription(of: completedView.body)
        let failedBody = testMirrorDescription(of: failedView.body)

        assertTestDescription(checkingBody, contains: [
            "Checking startup recovery state...",
            "database-repair-startup-recovery-core-startup-recovery-checking"
        ])
        assertTestDescription(completedBody, contains: [
            "Startup recovery checked",
            "Kept active staging file",
            "database-repair-startup-recovery-core-startup-recovery-completed"
        ])
        assertTestDescription(failedBody, contains: [
            "Startup recovery failed",
            "Retry startup recovery",
            "database-repair-startup-recovery-core-retry-startup-recovery"
        ])
        assertTestDescription(completedBody, doesNotContain: ["Remove from index"])
        assertTestDescription(failedBody, doesNotContain: ["Download & retry"])
    }

    @MainActor
    func testDatabaseRepairRepairReindexMetadataCoreViewDoesNotExposeAdjacentCoreActionsWhenScanSessionExists() {
        let view = DBRepairConfirmView(
            repoPath: "/tmp/repo",
            scanSession: ScanSessionSnapshot.mainLoadingReindexFixture(status: .interrupted),
            mapping: .databaseRepairRepairMapping(kind: .db, rawContext: "database corrupted"),
            metadataRepairer: DatabaseRepairRecordingMetadataRepairer(
                result: .success(.databaseRepairRepairReportFixture())
            ),
            diagnosticsCollector: ShellRecordingDiagnosticsCollector(
                result: .success(.databaseRepairDiagnosticsFixture())
            ),
            errorMapper: DatabaseRepairRepairErrorMapper(mapping: .databaseRepairRepairMapping(kind: .db)),
            onCancel: {},
            onRepairSucceeded: {},
            onOpenRepositoryInFinder: {}
        )
        let body = testMirrorDescription(of: view.body)

        assertTestDescription(body, contains: [
            "Run Full Rescan",
            "Export diagnostics..."
        ])
        assertTestDescription(body, doesNotContain: [
            "Resume",
            "Clean up and retry",
            "Interrupted scan"
        ])
    }

    func testDatabaseRepairRepairReindexMetadataCoreCoreBridgeDeclaresRepairMetadataBoundary() async {
        let declaredBoundaries = await CoreBridge().declaredBoundaries()

        XCTAssertTrue(CoreBridgeBoundary.allCases.contains(.repairMetadata))
        XCTAssertTrue(declaredBoundaries.contains(.repairMetadata))
    }

    func testDatabaseRepairStartupRecoveryCoreCoreBridgeDeclaresStartupRecoveryBoundary() async {
        let declaredBoundaries = await CoreBridge().declaredBoundaries()

        XCTAssertTrue(CoreBridgeBoundary.allCases.contains(.recoverOnStartup))
        XCTAssertTrue(declaredBoundaries.contains(.recoverOnStartup))
    }
}

struct DatabaseRepairRepairRequest: Equatable {
    var repoPath: String
    var options: RepairOptionsSnapshot
}

actor DatabaseRepairRecordingMetadataRepairer: CoreMetadataRepairing {
    private let result: Result<RepairReportSnapshot, Error>
    private var recordedRequests: [DatabaseRepairRepairRequest] = []

    init(result: Result<RepairReportSnapshot, Error>) {
        self.result = result
    }

    func repairMetadata(repoPath: String, options: RepairOptionsSnapshot) async throws -> RepairReportSnapshot {
        recordedRequests.append(DatabaseRepairRepairRequest(repoPath: repoPath, options: options))
        return try result.get()
    }

    func requests() -> [DatabaseRepairRepairRequest] {
        recordedRequests
    }
}

private enum DatabaseRepairStartupRecoveryResult {
    case success(RecoveryReportSnapshot)
    case failure(Error)
}

private actor DatabaseRepairRecordingStartupRecoverer: CoreStartupRecovering {
    private var results: [DatabaseRepairStartupRecoveryResult]
    private var repoPaths: [String] = []

    init(result: DatabaseRepairStartupRecoveryResult) {
        results = [result]
    }

    init(results: [DatabaseRepairStartupRecoveryResult]) {
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

private actor DatabaseRepairRepairErrorMapper: CoreErrorMapping {
    private let mapping: CoreErrorMappingSnapshot

    init(mapping: CoreErrorMappingSnapshot) {
        self.mapping = mapping
    }

    func mapCoreError(_: CoreError) async -> CoreErrorMappingSnapshot {
        mapping
    }
}

private extension RepairReportSnapshot {
    static func databaseRepairRepairReportFixture() -> RepairReportSnapshot {
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
    static func databaseRepairDiagnosticsFixture() -> DiagnosticsSnapshotSnapshot {
        DiagnosticsSnapshotSnapshot(
            snapshotPath: ".areamatrix/diagnostics/database-repair-diagnostics.zip",
            createdAt: 1_778_000_000,
            warnings: ["paths redacted"]
        )
    }
}

private extension CoreErrorMappingSnapshot {
    static func databaseRepairRepairMapping(
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

    static func databaseRepairStartupRecoveryMapping(rawContext: String) -> CoreErrorMappingSnapshot {
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
