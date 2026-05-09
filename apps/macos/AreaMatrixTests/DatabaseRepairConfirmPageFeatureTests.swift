import XCTest
@testable import AreaMatrix

final class DatabaseRepairConfirmPageFeatureTests: XCTestCase {
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
            ),
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
        guard case .failed(let mapping) = model.diagnosticsState else {
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
}

struct S137RepairRequest: Equatable, Sendable {
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

private actor S137RepairErrorMapper: CoreErrorMapping {
    private let mapping: CoreErrorMappingSnapshot

    init(mapping: CoreErrorMappingSnapshot) {
        self.mapping = mapping
    }

    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
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
