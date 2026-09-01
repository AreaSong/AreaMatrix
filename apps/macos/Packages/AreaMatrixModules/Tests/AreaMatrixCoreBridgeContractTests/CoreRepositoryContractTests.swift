@testable import AreaMatrixCoreBridgeContract
import XCTest

final class CoreRepositoryContractTests: XCTestCase {
    func testRepositoryPathValidationPreservesStableValues() {
        let validation = RepoPathValidationSnapshot(
            repoPath: "/tmp/repository",
            exists: true,
            isDirectory: true,
            isReadable: true,
            isWritable: true,
            isEmpty: false,
            isInitialized: true,
            isInsideAreaMatrix: false,
            isICloudPath: false,
            hasUnfinishedScanSession: false,
            availableCapacityBytes: RepoPathValidationSnapshot.minimumUsableCapacityBytes,
            isExternalVolume: false,
            recommendedMode: .adoptExisting,
            issues: []
        )

        XCTAssertFalse(validation.hasInsufficientAvailableCapacity)
        XCTAssertFalse(validation.hasMissingEnvironmentChecks)
        XCTAssertEqual(validation.recommendedMode, .adoptExisting)
        XCTAssertEqual(validation, validation)
    }

    func testScanSessionAndInitializationDraftPreserveLifecycleState() {
        let scanSession = ScanSessionSnapshot(
            id: 7,
            kind: .reindex,
            status: .paused,
            lastPath: "/tmp/repository/note.md",
            inserted: 2,
            updated: 3,
            skipped: 1,
            startedAt: 10,
            updatedAt: 20,
            finishedAt: nil,
            errors: ["permission"]
        )
        let validation = RepoPathValidationSnapshot(
            repoPath: "/tmp/repository",
            exists: true,
            isDirectory: true,
            isReadable: true,
            isWritable: true,
            isEmpty: false,
            isInitialized: true,
            isInsideAreaMatrix: false,
            isICloudPath: false,
            hasUnfinishedScanSession: true,
            availableCapacityBytes: nil,
            isExternalVolume: nil,
            recommendedMode: nil,
            issues: [.unfinishedScanSession]
        )
        let draft = RepositoryInitializationDraft(
            validation: validation,
            mode: .adoptExisting,
            scanSession: scanSession
        )

        XCTAssertEqual(draft.mode, .adoptExisting)
        XCTAssertEqual(draft.scanSession?.status, .paused)
        XCTAssertTrue(draft.validation.hasMissingEnvironmentChecks)
        XCTAssertTrue(draft.validation.hasUnfinishedScanSession)
    }

    func testRepositoryCapabilityProtocolsCanBeImplementedWithoutGeneratedBindings() async throws {
        let repository = RepositoryContractDouble()

        let config = try await repository.loadConfig(repoPath: "/tmp/repository")
        let updatedConfig = try await repository.updateConfig(
            repoPath: "/tmp/repository",
            from: config,
            to: config
        )
        let validation = try await repository.validateRepoPath(repoPath: "/tmp/repository")
        let initializedValidation = try await repository.validateInitializedRepoPath(repoPath: "/tmp/repository")
        let scan = try await repository.latestScanSession(repoPath: "/tmp/repository")
        let report = try await repository.resumeScanSession(repoPath: "/tmp/repository", scanSessionId: 7)

        XCTAssertEqual(updatedConfig, config)
        XCTAssertEqual(validation.repoPath, "/tmp/repository")
        XCTAssertEqual(initializedValidation.isInitialized, true)
        XCTAssertEqual(scan?.id, 7)
        XCTAssertEqual(report.scanSessionId, 7)
    }
}

private struct RepositoryContractDouble: CoreConfigurationLoading, CoreConfigurationUpdating,
    CoreRepositoryPathValidating, CoreInitializedRepositoryPathValidating, CoreRepositoryInitializing,
    CoreScanSessionReading {
    func loadConfig(repoPath: String) async throws -> AppRepoConfigSnapshot {
        AppRepoConfigSnapshot(
            repoPath: repoPath,
            revision: 1,
            defaultMode: RepoInitModeSnapshot.createEmpty.rawValue,
            overviewOutput: "GeneratedOnly",
            aiEnabled: false,
            locale: "system",
            iCloudWarn: true,
            enableExtensionRules: true,
            enableKeywordRules: true,
            fallbackToInbox: false,
            allowReplaceDuringImport: false
        )
    }

    func updateConfig(
        repoPath _: String,
        from _: AppRepoConfigSnapshot,
        to updatedConfig: AppRepoConfigSnapshot
    ) async throws -> AppRepoConfigSnapshot {
        updatedConfig
    }

    func validateRepoPath(repoPath: String) async throws -> RepoPathValidationSnapshot {
        validation(repoPath: repoPath, initialized: false)
    }

    func validateInitializedRepoPath(repoPath: String) async throws -> RepoPathValidationSnapshot {
        validation(repoPath: repoPath, initialized: true)
    }

    func initializeEmptyRepository(repoPath _: String) async throws {}

    func adoptExistingRepository(repoPath _: String) async throws {}

    func latestScanSession(repoPath _: String) async throws -> ScanSessionSnapshot? {
        ScanSessionSnapshot(
            id: 7,
            kind: .reindex,
            status: .completed,
            lastPath: nil,
            inserted: 1,
            updated: 0,
            skipped: 0,
            startedAt: 1,
            updatedAt: 2,
            finishedAt: 3,
            errors: []
        )
    }

    func resumeScanSession(repoPath _: String, scanSessionId: Int64) async throws -> ReindexReportSnapshot {
        ReindexReportSnapshot(scanSessionId: scanSessionId, inserted: 1, updated: 0, skipped: 0, errors: [])
    }

    private func validation(repoPath: String, initialized: Bool) -> RepoPathValidationSnapshot {
        RepoPathValidationSnapshot(
            repoPath: repoPath,
            exists: true,
            isDirectory: true,
            isReadable: true,
            isWritable: true,
            isEmpty: !initialized,
            isInitialized: initialized,
            isInsideAreaMatrix: false,
            isICloudPath: false,
            hasUnfinishedScanSession: false,
            availableCapacityBytes: 1024,
            isExternalVolume: false,
            recommendedMode: initialized ? nil : .createEmpty,
            issues: []
        )
    }
}
