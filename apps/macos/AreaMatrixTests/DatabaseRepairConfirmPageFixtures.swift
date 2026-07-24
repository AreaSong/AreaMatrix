@testable import AreaMatrix

extension RepairOptionsSnapshot {
    static func testFixture(
        preserveDiagnosticsSnapshot: Bool = true,
        preflightToken: String = "repair-preflight-token",
        repositoryLocalePolicy: String = "system"
    ) -> RepairOptionsSnapshot {
        RepairOptionsSnapshot(
            preserveDiagnosticsSnapshot: preserveDiagnosticsSnapshot,
            preflightToken: preflightToken,
            repositoryLocalePolicy: repositoryLocalePolicy
        )
    }

    static func databaseRepairMetadataFixture(
        preflightToken: String = "repair-preflight-token",
        repositoryLocalePolicy: String = "system"
    ) -> RepairOptionsSnapshot {
        testFixture(
            preserveDiagnosticsSnapshot: true,
            preflightToken: preflightToken,
            repositoryLocalePolicy: repositoryLocalePolicy
        )
    }
}

extension RepairMetadataPreflightSnapshot {
    static func testFixture(
        localeState: RepairMetadataLocaleStateSnapshot = .healthy,
        repositoryLocalePolicy: String? = "system",
        unsupportedLocale: String? = nil,
        requiresExplicitLocaleSelection: Bool = false,
        preflightToken: String = "repair-preflight-token"
    ) -> RepairMetadataPreflightSnapshot {
        RepairMetadataPreflightSnapshot(
            localeState: localeState,
            repositoryLocalePolicy: repositoryLocalePolicy,
            unsupportedLocale: unsupportedLocale,
            requiresExplicitLocaleSelection: requiresExplicitLocaleSelection,
            preflightToken: preflightToken
        )
    }

    static func databaseRepairHealthyPreflightFixture() -> RepairMetadataPreflightSnapshot {
        testFixture()
    }
}

extension RepairReportSnapshot {
    static func testFixture(
        diagnosticsSnapshotPath: String? = ".areamatrix/diagnostics/repair.zip",
        outcome: String = "Verified"
    ) -> RepairReportSnapshot {
        RepairReportSnapshot(
            diagnosticsSnapshotPath: diagnosticsSnapshotPath,
            outcome: outcome
        )
    }

    static func databaseRepairRepairReportFixture() -> RepairReportSnapshot {
        testFixture()
    }
}

extension ReindexReportSnapshot {
    static func databaseRepairReindexReportFixture(
        scanSessionId: Int64? = 7,
        inserted: Int64 = 1,
        updated: Int64 = 2,
        skipped: Int64 = 3,
        errors: [String] = []
    ) -> ReindexReportSnapshot {
        ReindexReportSnapshot(
            scanSessionId: scanSessionId,
            inserted: inserted,
            updated: updated,
            skipped: skipped,
            errors: errors
        )
    }
}

extension DiagnosticsSnapshotSnapshot {
    static func databaseRepairDiagnosticsFixture() -> DiagnosticsSnapshotSnapshot {
        .testFixture(
            snapshotPath: ".areamatrix/diagnostics/database-repair-diagnostics.db",
            createdAt: 1_778_000_000,
            warnings: ["index.db-wal disappeared during snapshot"]
        )
    }
}

extension CoreErrorMappingSnapshot {
    static func databaseRepairRepairMapping(
        kind: CoreErrorKindSnapshot,
        rawContext: String = "db corrupt"
    ) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: kind,
            userMessage: "Repository metadata needs repair",
            severity: .critical,
            suggestedAction: "Run a full metadata rescan after preserving diagnostics.",
            recoverability: .userActionRequired,
            rawContext: rawContext
        )
    }

    static func databaseRepairStartupRecoveryMapping(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: .db,
            userMessage: "Startup recovery could not finish",
            severity: .medium,
            suggestedAction: "Retry startup recovery before running metadata repair.",
            recoverability: .retryable,
            rawContext: rawContext
        )
    }
}
