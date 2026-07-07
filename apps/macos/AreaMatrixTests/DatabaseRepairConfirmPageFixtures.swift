@testable import AreaMatrix

extension RepairOptionsSnapshot {
    static func testFixture(
        fullRescan: Bool = true,
        preserveDiagnosticsSnapshot: Bool = true
    ) -> RepairOptionsSnapshot {
        RepairOptionsSnapshot(
            fullRescan: fullRescan,
            preserveDiagnosticsSnapshot: preserveDiagnosticsSnapshot
        )
    }

    static func databaseRepairFullRescanFixture() -> RepairOptionsSnapshot {
        testFixture(fullRescan: true, preserveDiagnosticsSnapshot: true)
    }
}

extension RepairReportSnapshot {
    static func testFixture(
        scanSessionId: Int64 = 7,
        inserted: Int64 = 1,
        updated: Int64 = 2,
        skipped: Int64 = 3,
        errors: [String] = []
    ) -> RepairReportSnapshot {
        RepairReportSnapshot(
            scanSessionId: scanSessionId,
            diagnosticsSnapshotPath: ".areamatrix/diagnostics/repair.zip",
            inserted: inserted,
            updated: updated,
            skipped: skipped,
            errors: errors
        )
    }

    static func databaseRepairRepairReportFixture() -> RepairReportSnapshot {
        testFixture()
    }
}

extension DiagnosticsSnapshotSnapshot {
    static func databaseRepairDiagnosticsFixture() -> DiagnosticsSnapshotSnapshot {
        .testFixture(
            snapshotPath: ".areamatrix/diagnostics/database-repair-diagnostics.zip",
            createdAt: 1_778_000_000,
            warnings: ["paths redacted"]
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
