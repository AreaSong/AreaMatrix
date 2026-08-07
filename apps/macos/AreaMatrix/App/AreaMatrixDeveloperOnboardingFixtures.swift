import AreaMatrixCoreBridgeContract
import Foundation

#if DEBUG
enum DeveloperOnboardingScenarioFixture {
    static let validation = RepoPathValidationSnapshot(
        repoPath: AreaMatrixPreviewFixtures.repositoryPath,
        exists: true,
        isDirectory: true,
        isReadable: true,
        isWritable: true,
        isEmpty: false,
        isInitialized: false,
        isInsideAreaMatrix: false,
        isICloudPath: false,
        hasUnfinishedScanSession: false,
        availableCapacityBytes: 128 * 1024 * 1024 * 1024,
        isExternalVolume: false,
        recommendedMode: .adoptExisting,
        issues: [.nonEmptyDirectory]
    )

    static let runningScan = scanSession(status: .running, finishedAt: nil)
    static let completedScan = scanSession(status: .completed, finishedAt: 1_778_738_520)

    static let draft = RepositoryInitializationDraft(
        validation: validation,
        mode: .adoptExisting,
        scanSession: runningScan
    )

    static let recoveryReport = RecoveryReportSnapshot(
        cleanedStagingFiles: 2,
        revertedStagingDbRows: 1,
        warnings: []
    )

    static let result = RepositoryInitializationResult(
        repoPath: AreaMatrixPreviewFixtures.repositoryPath,
        mode: .adoptExisting,
        scanSession: completedScan,
        recoveryReport: recoveryReport
    )

    static let databaseFailure = CoreErrorMappingSnapshot(
        kind: .db,
        userMessage: L10n.message("core.error.Db.message"),
        severity: .critical,
        suggestedAction: L10n.message("core.error.Db.action"),
        recoverability: .userActionRequired,
        rawContext: "database disk image is malformed"
    )

    static let recoveryFailure = CoreErrorMappingSnapshot(
        kind: .stagingRecoveryRequired,
        userMessage: L10n.message("core.error.StagingRecoveryRequired.message"),
        severity: .high,
        suggestedAction: L10n.message("core.error.StagingRecoveryRequired.action"),
        recoverability: .userActionRequired,
        rawContext: ".areamatrix/staging/developer-scenario"
    )

    static let diagnostics = DiagnosticsSnapshotSnapshot(
        snapshotPath: ".areamatrix/diagnostics/developer-onboarding.zip",
        createdAt: 1_778_738_600,
        warnings: []
    )

    private static func scanSession(
        status: ScanSessionStatusSnapshot,
        finishedAt: Int64?
    ) -> ScanSessionSnapshot {
        ScanSessionSnapshot(
            id: 42,
            kind: .adopt,
            status: status,
            lastPath: "docs/architecture.md",
            inserted: 128,
            updated: 12,
            skipped: 3,
            startedAt: 1_778_738_400,
            updatedAt: 1_778_738_500,
            finishedAt: finishedAt,
            errors: []
        )
    }
}

struct DeveloperOnboardingCoreFixture: CoreMetadataRepairing,
    CoreRepositoryReindexing,
    CoreStartupRecovering {
    func preflightRepairMetadata(repoPath _: String) async throws -> RepairMetadataPreflightSnapshot {
        RepairMetadataPreflightSnapshot(
            localeState: .databaseCorrupt,
            repositoryLocalePolicy: "en",
            unsupportedLocale: nil,
            requiresExplicitLocaleSelection: false,
            preflightToken: "developer-onboarding-preflight"
        )
    }

    func repairMetadata(repoPath _: String, options _: RepairOptionsSnapshot) async throws -> RepairReportSnapshot {
        RepairReportSnapshot(
            diagnosticsSnapshotPath: ".areamatrix/diagnostics/developer-repair.zip",
            outcome: "Rebuilt"
        )
    }

    func reindexRepository(repoPath _: String) async throws -> ReindexReportSnapshot {
        ReindexReportSnapshot(
            scanSessionId: 43,
            inserted: 128,
            updated: 12,
            skipped: 3,
            errors: []
        )
    }

    func recoverOnStartup(repoPath _: String) async throws -> RecoveryReportSnapshot {
        DeveloperOnboardingScenarioFixture.recoveryReport
    }
}

actor DeveloperOnboardingDiagnosticsCollector: CoreDiagnosticsCollecting {
    func createDiagnosticsSnapshot(repoPath _: String) async throws -> DiagnosticsSnapshotSnapshot {
        DeveloperOnboardingScenarioFixture.diagnostics
    }
}
#endif
