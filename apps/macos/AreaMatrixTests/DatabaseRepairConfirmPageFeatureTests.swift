@testable import AreaMatrix
import XCTest

final class DatabaseRepairConfirmPageFeatureTests: XCTestCase {
    @MainActor
    func testDatabaseRepairStartupRecoveryCoreStartupRecoveryRunsRealCoreBridgeBoundaryBeforeRepair() async {
        let report = RecoveryReportSnapshot.testFixture(
            cleanedStagingFiles: 2,
            revertedStagingDbRows: 1,
            warnings: ["Kept recoverable staging file"]
        )
        let recoverer = RecordingCoreStartupRecoverer(result: .success(report))
        let repairer = DatabaseRepairRecordingMetadataRepairer(result: .success(.databaseRepairRepairReportFixture()))
        let model = DatabaseRepairConfirmModel(
            repoPath: "/tmp/repo",
            scanSession: nil,
            mapping: nil,
            lastOpenedAt: nil,
            metadataRepairer: repairer,
            repositoryReindexer: RepairRecordingReindexer(),
            startupRecoverer: recoverer,
            repositoryWriteCoordinator: RepositoryWriteCoordinator(),
            diagnosticsCollector: ShellRecordingDiagnosticsCollector(
                result: .success(.databaseRepairDiagnosticsFixture())
            ),
            errorMapper: StaticCoreErrorMapper(mapping: .databaseRepairRepairMapping(kind: .db))
        )

        await model.runStartupRecoveryCheckIfNeeded()

        await recoverer.assertRequestedRepoPaths(["/tmp/repo"])
        XCTAssertEqual(model.startupRecoveryState, .completed(report))
        await repairer.assertNoMetadataRepairRequests()
    }

    @MainActor
    func testDatabaseRepairStartupRecoveryCoreStartupRecoveryFailureMapsErrorAndCanRetry() async {
        let mapping = CoreErrorMappingSnapshot.databaseRepairStartupRecoveryMapping(rawContext: "database locked")
        let recoverer = RecordingCoreStartupRecoverer(results: [
            .failure(CoreError.Db(message: "database locked")),
            .success(.testFixture())
        ])
        let model = DatabaseRepairConfirmModel(
            repoPath: "/tmp/repo",
            scanSession: nil,
            mapping: nil,
            lastOpenedAt: nil,
            metadataRepairer: DatabaseRepairRecordingMetadataRepairer(
                result: .success(.databaseRepairRepairReportFixture())
            ),
            repositoryReindexer: RepairRecordingReindexer(),
            startupRecoverer: recoverer,
            repositoryWriteCoordinator: RepositoryWriteCoordinator(),
            diagnosticsCollector: ShellRecordingDiagnosticsCollector(
                result: .success(.databaseRepairDiagnosticsFixture())
            ),
            errorMapper: StaticCoreErrorMapper(mapping: mapping)
        )

        await model.runStartupRecoveryCheckIfNeeded()
        XCTAssertEqual(model.startupRecoveryState, .failed(mapping))

        await model.runStartupRecoveryCheckIfNeeded()
        await recoverer.assertRequestedRepoPaths(["/tmp/repo"])

        await model.retryStartupRecovery()
        await recoverer.assertRequestedRepoPaths(["/tmp/repo", "/tmp/repo"])
        XCTAssertEqual(model.startupRecoveryState, .completed(nil))
    }

    @MainActor
    func testDatabaseRepairRepairReindexMetadataCoreSeparatesRepairAndRescanConfirmations() async {
        let report = RepairReportSnapshot.testFixture(outcome: "Verified")
        let repairer = DatabaseRepairRecordingMetadataRepairer(result: .success(report))
        let reindexer = RepairRecordingReindexer()
        let model = DatabaseRepairConfirmModel(
            repoPath: "/tmp/repo",
            scanSession: nil,
            mapping: nil,
            lastOpenedAt: nil,
            metadataRepairer: repairer,
            repositoryReindexer: reindexer,
            startupRecoverer: StaticStartupRecoverer(),
            repositoryWriteCoordinator: RepositoryWriteCoordinator(),
            diagnosticsCollector: ShellRecordingDiagnosticsCollector(
                result: .success(.databaseRepairDiagnosticsFixture())
            ),
            errorMapper: StaticCoreErrorMapper(mapping: .databaseRepairRepairMapping(kind: .db))
        )

        await model.runMetadataRepair()
        await repairer.assertNoMetadataRepairRequests()
        XCTAssertEqual(model.repairState, .idle)

        await model.loadRepairPreflightIfNeeded()
        model.isMetadataSafetyConfirmed = true
        await model.runMetadataRepair()

        await repairer.assertPreflightRequests(["/tmp/repo"])
        await repairer.assertMetadataRepairRequests([
            DatabaseRepairMetadataRepairRequest(
                repoPath: "/tmp/repo",
                options: .databaseRepairMetadataFixture()
            )
        ])
        XCTAssertEqual(model.repairState, .succeeded(report))
        await reindexer.assertReindexRequests([])

        await model.runRescan()
        await reindexer.assertReindexRequests([])
        model.isRescanConfirmed = true
        await model.runRescan()
        await reindexer.assertReindexRequests(["/tmp/repo"])
        XCTAssertTrue(model.rescanState.isSucceeded)
    }

    @MainActor
    func testDatabaseRepairRepairReindexMetadataCoreRepairFailureMapsCoreErrorAndStaysRetryable() async {
        let mapping = CoreErrorMappingSnapshot.databaseRepairRepairMapping(
            kind: .permissionDenied,
            rawContext: "/tmp/repo/.areamatrix/index.db"
        )
        let repairer = DatabaseRepairRecordingMetadataRepairer(
            preflightResults: [
                .success(.databaseRepairHealthyPreflightFixture()),
                .success(.databaseRepairHealthyPreflightFixture())
            ],
            result: .failure(CoreError.PermissionDenied(path: "/tmp/repo/.areamatrix/index.db"))
        )
        let model = DatabaseRepairConfirmModel(
            repoPath: "/tmp/repo",
            scanSession: nil,
            mapping: nil,
            lastOpenedAt: nil,
            metadataRepairer: repairer,
            repositoryReindexer: RepairRecordingReindexer(),
            startupRecoverer: StaticStartupRecoverer(),
            repositoryWriteCoordinator: RepositoryWriteCoordinator(),
            diagnosticsCollector: ShellRecordingDiagnosticsCollector(
                result: .success(.databaseRepairDiagnosticsFixture())
            ),
            errorMapper: StaticCoreErrorMapper(mapping: mapping)
        )

        await model.loadRepairPreflightIfNeeded()
        model.isMetadataSafetyConfirmed = true
        await model.runMetadataRepair()

        XCTAssertEqual(model.repairState, .failed(mapping))
        XCTAssertEqual(model.primaryButtonTitle, "Retry Metadata Repair")
        XCTAssertTrue(model.canRunMetadataRepair)
        await repairer.assertPreflightRequests(["/tmp/repo", "/tmp/repo"])
    }

    @MainActor
    func testDatabaseRepairMetadataAbsentStillUsesMetadataOnlyRepairCopy() async {
        let repairer = DatabaseRepairRecordingMetadataRepairer(
            preflightResults: [.success(.testFixture(
                localeState: .metadataAbsent,
                repositoryLocalePolicy: nil,
                requiresExplicitLocaleSelection: true
            ))],
            result: .success(.testFixture(outcome: "Initialized"))
        )
        let model = DatabaseRepairConfirmModel(
            repoPath: "/tmp/repo",
            scanSession: nil,
            mapping: .databaseRepairRepairMapping(kind: .repoNotInitialized),
            lastOpenedAt: nil,
            metadataRepairer: repairer,
            repositoryReindexer: RepairRecordingReindexer(),
            startupRecoverer: StaticStartupRecoverer(),
            repositoryWriteCoordinator: RepositoryWriteCoordinator(),
            diagnosticsCollector: ShellRecordingDiagnosticsCollector(
                result: .success(.databaseRepairDiagnosticsFixture())
            ),
            errorMapper: StaticCoreErrorMapper(mapping: .databaseRepairRepairMapping(kind: .db))
        )

        await model.loadRepairPreflightIfNeeded()
        XCTAssertEqual(model.primaryButtonTitle, "Repair Metadata")
        XCTAssertFalse(model.canRunMetadataRepair)
        model.selectedRecoveryLanguage = .zhHans
        model.isMetadataSafetyConfirmed = true
        await model.runMetadataRepair()

        await repairer.assertMetadataRepairRequests([
            DatabaseRepairMetadataRepairRequest(
                repoPath: "/tmp/repo",
                options: .databaseRepairMetadataFixture(repositoryLocalePolicy: "zh-Hans")
            )
        ])
        XCTAssertTrue(model.repairState.isSucceeded)
    }
}

extension DatabaseRepairConfirmPageFeatureTests {
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
            repositoryReindexer: RepairRecordingReindexer(),
            startupRecoverer: StaticStartupRecoverer(),
            repositoryWriteCoordinator: RepositoryWriteCoordinator(),
            diagnosticsCollector: diagnosticsCollector,
            errorMapper: StaticCoreErrorMapper(mapping: .databaseRepairRepairMapping(kind: .permissionDenied))
        )

        await model.loadRepairPreflightIfNeeded()
        model.isMetadataSafetyConfirmed = true
        await model.collectDiagnostics()
        await diagnosticsCollector.assertNoRepoPathRequests()
        XCTAssertTrue(model.canRunMetadataRepair)

        model.requestDiagnosticsExport()
        await model.collectDiagnostics()

        await diagnosticsCollector.assertRequestedRepoPaths(["/tmp/repo"])
        guard case let .failed(mapping) = model.diagnosticsState else {
            return XCTFail("expected diagnostics failure")
        }
        XCTAssertEqual(mapping.kind, .permissionDenied)
        XCTAssertFalse(model.canRunMetadataRepair)
    }

    @MainActor
    func testCancelledDatabaseRepairDiagnosticsIgnoresLateCollectorResult() async {
        let collector = SuspendedDiagnosticsCollector(result: .success(.databaseRepairDiagnosticsFixture()))
        let model = DatabaseRepairConfirmModel(
            repoPath: "/tmp/repo",
            scanSession: nil,
            mapping: nil,
            lastOpenedAt: nil,
            metadataRepairer: DatabaseRepairRecordingMetadataRepairer(
                result: .success(.databaseRepairRepairReportFixture())
            ),
            repositoryReindexer: RepairRecordingReindexer(),
            startupRecoverer: StaticStartupRecoverer(),
            repositoryWriteCoordinator: RepositoryWriteCoordinator(),
            diagnosticsCollector: collector,
            errorMapper: StaticCoreErrorMapper(mapping: .databaseRepairRepairMapping(kind: .db))
        )
        model.requestDiagnosticsExport()

        let collection = Task { await model.collectDiagnostics() }
        await collector.waitUntilStarted()
        model.cancelDiagnosticsExport()
        await collector.finish()
        await collection.value

        XCTAssertEqual(model.diagnosticsState, .idle)
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
            repositoryReindexer: RepairRecordingReindexer(),
            startupRecoverer: StaticStartupRecoverer(),
            repositoryWriteCoordinator: RepositoryWriteCoordinator(),
            diagnosticsCollector: ShellRecordingDiagnosticsCollector(
                result: .success(.databaseRepairDiagnosticsFixture())
            ),
            errorMapper: StaticCoreErrorMapper(mapping: .databaseRepairRepairMapping(kind: .db)),
            onCancel: {},
            onRepairSucceeded: {},
            onOpenRepositoryInFinder: {}
        )
        assertTestMirrorDescription(of: view.body, contains: [
            "Repair Repository Metadata?",
            "AreaMatrix cannot read the repository metadata database",
            "Repair Metadata",
            "Export diagnostics...",
            "database-repair-run-metadata-repair",
            "database-repair-confirm-metadata-only"
        ], doesNotContain: [
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
            state: .completed(.testFixture(
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

        assertTestMirrorDescription(of: checkingView.body, contains: [
            "Checking startup recovery state...",
            "database-repair-startup-recovery-core-startup-recovery-checking"
        ])
        assertTestMirrorDescription(of: completedView.body, contains: [
            "Startup recovery checked",
            "Kept active staging file",
            "database-repair-startup-recovery-core-startup-recovery-completed"
        ], doesNotContain: ["Remove from index"])
        assertTestMirrorDescription(of: failedView.body, contains: [
            "Startup recovery failed",
            "Retry startup recovery",
            "database-repair-startup-recovery-core-retry-startup-recovery"
        ], doesNotContain: ["Download & retry"])
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
            repositoryReindexer: RepairRecordingReindexer(),
            startupRecoverer: StaticStartupRecoverer(),
            repositoryWriteCoordinator: RepositoryWriteCoordinator(),
            diagnosticsCollector: ShellRecordingDiagnosticsCollector(
                result: .success(.databaseRepairDiagnosticsFixture())
            ),
            errorMapper: StaticCoreErrorMapper(mapping: .databaseRepairRepairMapping(kind: .db)),
            onCancel: {},
            onRepairSucceeded: {},
            onOpenRepositoryInFinder: {}
        )
        assertTestMirrorDescription(of: view.body, contains: [
            "Repair Metadata",
            "Export diagnostics..."
        ], doesNotContain: [
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
