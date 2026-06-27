@testable import AreaMatrix
import Foundation
import XCTest

final class DatabaseRepairIntegrationTests: XCTestCase {
    @MainActor
    func testDatabaseRepairPageIntegrationConnectsDbRepairEntryConfirmedFullRescanAndMainListExit() async throws {
        let context = try await DatabaseRepairIntegrationSuccessContext.make()
        defer { context.cleanup() }

        let repairRoute = try context.openRepairRoute()
        let repairModel = context.makeRepairModel(repairRoute)

        try await context.verifyStartupDiagnosticsAndFullRescan(repairModel)
        try await context.verifyMainLoadingAndMainListExit(repairRoute)
    }

    @MainActor
    func testDatabaseRepairPageIntegrationKeepsFailureAndCancelInsideRepairBoundary() async {
        let mapping = CoreErrorMappingSnapshot.databaseRepairIntegrationMapping(
            kind: .permissionDenied,
            severity: .critical,
            recoverability: .userActionRequired,
            rawContext: "/tmp/repo/.areamatrix/index.db"
        )
        let repairer = RecordingMetadataRepairer(
            result: .failure(CoreError.PermissionDenied(path: "/tmp/repo/.areamatrix/index.db"))
        )
        let finder = ShellRecordingFinderOpener()
        let shell = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            finderOpener: finder,
            helpOpener: ShellNoopWelcomeHelpOpener()
        )
        shell.route = .mainRepoError("/tmp/repo", mapping)
        shell.openMainRepositoryRepair(repoPath: "/tmp/repo")
        guard case let .dbRepairConfirm(repairRoute) = shell.route else {
            return XCTFail("Expected database-repair repair route, got \(shell.route)")
        }

        let repairModel = DatabaseRepairConfirmModel(
            repoPath: repairRoute.repoPath,
            scanSession: repairRoute.scanSession,
            mapping: repairRoute.mapping,
            lastOpenedAt: nil,
            metadataRepairer: repairer,
            startupRecoverer: MainLoadingStaticStartupRecoverer(),
            diagnosticsCollector: ShellRecordingDiagnosticsCollector(
                result: .success(.databaseRepairIntegrationDiagnostics)
            ),
            errorMapper: StaticRepairErrorMapper(mapping: mapping)
        )

        repairModel.isMetadataSafetyConfirmed = true
        await repairModel.runFullRescan()
        let requests = await repairer.requests()

        XCTAssertEqual(requests, [
            DatabaseRepairIntegrationRepairRequest(
                repoPath: "/tmp/repo",
                options: RepairOptionsSnapshot(fullRescan: true, preserveDiagnosticsSnapshot: true)
            )
        ])
        XCTAssertEqual(repairModel.repairState, .failed(mapping))
        XCTAssertEqual(repairModel.primaryButtonTitle, "Retry Full Rescan")
        XCTAssertEqual(shell.route, .dbRepairConfirm(repairRoute))

        shell.revealMainRepositoryFolder(repoPath: repairRoute.repoPath)
        XCTAssertEqual(finder.openedRepoPaths, ["/tmp/repo"])

        shell.returnFromDatabaseRepair(repairRoute)
        XCTAssertEqual(shell.route, .mainRepoError("/tmp/repo", mapping))
    }
}

private struct DatabaseRepairIntegrationRepairRequest: Equatable {
    var repoPath: String
    var options: RepairOptionsSnapshot
}

private actor RecordingMetadataRepairer: CoreMetadataRepairing {
    private let result: Result<RepairReportSnapshot, Error>
    private var recordedRequests: [DatabaseRepairIntegrationRepairRequest] = []

    init(result: Result<RepairReportSnapshot, Error>) {
        self.result = result
    }

    func repairMetadata(repoPath: String, options: RepairOptionsSnapshot) async throws -> RepairReportSnapshot {
        recordedRequests.append(DatabaseRepairIntegrationRepairRequest(repoPath: repoPath, options: options))
        return try result.get()
    }

    func requests() -> [DatabaseRepairIntegrationRepairRequest] {
        recordedRequests
    }
}

private actor StaticRepairErrorMapper: CoreErrorMapping {
    private let mapping: CoreErrorMappingSnapshot

    init(mapping: CoreErrorMappingSnapshot) {
        self.mapping = mapping
    }

    func mapCoreError(_: CoreError) async -> CoreErrorMappingSnapshot {
        mapping
    }
}

private struct DatabaseRepairIntegrationSuccessContext {
    let repoURL: URL
    let readmeURL: URL
    let specURL: URL
    let beforeRepair: [UserFileSnapshot]
    let mapping: CoreErrorMappingSnapshot
    let bridge: CoreBridge
    let writer: ShellRecordingSettingsWriter
    let opener: DatabaseRepairPausingRepositoryOpener
    let shell: OnboardingModel

    @MainActor
    static func make() async throws -> DatabaseRepairIntegrationSuccessContext {
        let repoURL = try databaseRepairIntegrationTemporaryDirectory()
        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let readmeURL = try databaseRepairIntegrationWriteRepoFile(
            repoURL,
            relativePath: "README.md",
            contents: "user readme\n"
        )
        let specURL = try databaseRepairIntegrationWriteRepoFile(
            repoURL,
            relativePath: "docs/spec.txt",
            contents: "spec\n"
        )
        let mapping = CoreErrorMappingSnapshot.databaseRepairIntegrationMapping(
            kind: .db,
            severity: .critical,
            recoverability: .fatal,
            rawContext: "database corrupted"
        )
        let writer = ShellRecordingSettingsWriter()
        let opener = DatabaseRepairPausingRepositoryOpener(bridge: bridge)
        let shell = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            settingsWriter: writer,
            emptyRepositoryOpener: opener,
            helpOpener: ShellNoopWelcomeHelpOpener()
        )
        shell.route = .mainRepoError(repoURL.path, mapping)

        return try DatabaseRepairIntegrationSuccessContext(
            repoURL: repoURL,
            readmeURL: readmeURL,
            specURL: specURL,
            beforeRepair: databaseRepairIntegrationUserFileSnapshot([readmeURL, specURL]),
            mapping: mapping,
            bridge: bridge,
            writer: writer,
            opener: opener,
            shell: shell
        )
    }

    @MainActor
    func openRepairRoute() throws -> DatabaseRepairRouteState {
        shell.openMainRepositoryRepair(repoPath: repoURL.path)
        guard case let .dbRepairConfirm(repairRoute) = shell.route else {
            throw DatabaseRepairIntegrationFailure
                .unexpectedRoute("Expected database-repair repair route, got \(shell.route)")
        }

        XCTAssertEqual(repairRoute.mapping, mapping)
        XCTAssertEqual(repairRoute.returnRoute, .mainRepoError(mapping))
        return repairRoute
    }

    @MainActor
    func makeRepairModel(_ repairRoute: DatabaseRepairRouteState) -> DatabaseRepairConfirmModel {
        DatabaseRepairConfirmModel(
            repoPath: repairRoute.repoPath,
            scanSession: repairRoute.scanSession,
            mapping: repairRoute.mapping,
            lastOpenedAt: 1_777_000_000,
            metadataRepairer: bridge,
            startupRecoverer: bridge,
            diagnosticsCollector: bridge,
            errorMapper: bridge
        )
    }

    @MainActor
    func verifyStartupDiagnosticsAndFullRescan(_ repairModel: DatabaseRepairConfirmModel) async throws {
        await repairModel.runStartupRecoveryCheckIfNeeded()
        XCTAssertEqual(repairModel.startupRecoveryState, .completed(nil))
        XCTAssertFalse(repairModel.canRunFullRescan)

        try await verifyDiagnosticsExport(repairModel)
        try await verifyConfirmedFullRescan(repairModel)
        try await verifyIndexedFilesAndDeclaredBoundaries()
    }

    @MainActor
    func verifyMainLoadingAndMainListExit(_ repairRoute: DatabaseRepairRouteState) async throws {
        let retryTask = Task {
            await shell.retryMainRepositoryFromError(repoPath: repairRoute.repoPath)
        }
        await opener.waitUntilStarted()
        let loadingState = await waitForMainLoadingState(shell) { $0.repoPath == repairRoute.repoPath }
        XCTAssertEqual(loadingState?.repoPath, repairRoute.repoPath)
        await opener.finishOpen()
        await retryTask.value

        let openRequests = await opener.requestedConfiguredRepoPaths()
        guard case let .mainList(opening) = shell.route else {
            throw DatabaseRepairIntegrationFailure.unexpectedRoute("Expected main-list main-list, got \(shell.route)")
        }
        XCTAssertEqual(openRequests, [repoURL.path])
        XCTAssertEqual(opening.config.repoPath, repoURL.path)
        XCTAssertEqual(opening.tree.totalFileCount, 2)
        XCTAssertEqual(writer.savedRepoPaths, [repoURL.path])
        XCTAssertEqual(writer.successfulRepoOpens.map(\.repoPath), [repoURL.path])
    }

    func cleanup() {
        removeTestTemporaryItems(repoURL)
    }

    @MainActor
    private func verifyDiagnosticsExport(_ repairModel: DatabaseRepairConfirmModel) async throws {
        repairModel.requestDiagnosticsExport()
        await repairModel.collectDiagnostics()
        guard case let .collected(diagnostics) = repairModel.diagnosticsState else {
            throw DatabaseRepairIntegrationFailure.unexpectedRoute("Expected diagnostics before repair")
        }
        XCTAssertTrue(diagnostics.snapshotPath.hasPrefix(".areamatrix/diagnostics/index-"))
        let snapshotURL = repoURL.appendingPathComponent(diagnostics.snapshotPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshotURL.path))
    }

    @MainActor
    private func verifyConfirmedFullRescan(_ repairModel: DatabaseRepairConfirmModel) async throws {
        repairModel.isMetadataSafetyConfirmed = true
        XCTAssertTrue(repairModel.canRunFullRescan)
        await repairModel.runFullRescan()
        guard case let .succeeded(report) = repairModel.repairState else {
            throw DatabaseRepairIntegrationFailure
                .unexpectedRoute("Expected repair success, got \(repairModel.repairState)")
        }

        XCTAssertNotNil(report.scanSessionId)
        XCTAssertTrue(report.diagnosticsSnapshotPath?.hasPrefix(".areamatrix/diagnostics/index-") == true)
        XCTAssertEqual(report.inserted, 2)
        XCTAssertEqual(report.updated, 0)
        XCTAssertEqual(report.errors, [])
        XCTAssertEqual(try databaseRepairIntegrationUserFileSnapshot([readmeURL, specURL]), beforeRepair)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("AREAMATRIX.md").path))
    }

    private func verifyIndexedFilesAndDeclaredBoundaries() async throws {
        let files = try await bridge.listFiles(repoPath: repoURL.path, filter: .databaseRepairIntegrationAllFiles)
        XCTAssertEqual(Set(files.map(\.path)), ["README.md", "docs/spec.txt"])
        XCTAssertEqual(Set(files.map(\.storageMode)), ["Indexed"])
        XCTAssertEqual(Set(files.map(\.origin)), ["External"])

        let declaredBoundaries = await bridge.declaredBoundaries()
        XCTAssertTrue(declaredBoundaries.contains(.repairMetadata))
        XCTAssertTrue(declaredBoundaries.contains(.reindexFromFilesystem))
        XCTAssertTrue(declaredBoundaries.contains(.recoverOnStartup))
    }
}

private actor DatabaseRepairPausingRepositoryOpener: CoreEmptyRepositoryOpening {
    private let bridge: CoreBridge
    private var configuredPaths: [String] = []
    private var didStart = false
    private var didFinish = false
    private var startContinuations: [CheckedContinuation<Void, Never>] = []
    private var finishContinuation: CheckedContinuation<Void, Never>?

    init(bridge: CoreBridge) {
        self.bridge = bridge
    }

    func openConfiguredRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        configuredPaths.append(repoPath)
        await pauseUntilFinished()
        return try await bridge.openConfiguredRepository(repoPath: repoPath)
    }

    func openEmptyRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        try await openConfiguredRepository(repoPath: repoPath)
    }

    func openAdoptedRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        try await openConfiguredRepository(repoPath: repoPath)
    }

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { startContinuations.append($0) }
    }

    func finishOpen() {
        didFinish = true
        finishContinuation?.resume()
        finishContinuation = nil
    }

    func requestedConfiguredRepoPaths() -> [String] {
        configuredPaths
    }

    private func pauseUntilFinished() async {
        didStart = true
        resumeStartContinuations()
        guard !didFinish else { return }
        await withCheckedContinuation { finishContinuation = $0 }
    }

    private func resumeStartContinuations() {
        let continuations = startContinuations
        startContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }
}

private struct UserFileSnapshot: Equatable {
    var path: String
    var data: Data
}

private enum DatabaseRepairIntegrationFailure: Error {
    case unexpectedRoute(String)
}

private extension FileFilterSnapshot {
    static let databaseRepairIntegrationAllFiles = FileFilterSnapshot(
        category: nil,
        includeDeleted: false,
        importedAfter: nil,
        importedBefore: nil,
        limit: 100,
        offset: 0
    )
}

private extension DiagnosticsSnapshotSnapshot {
    static let databaseRepairIntegrationDiagnostics = DiagnosticsSnapshotSnapshot(
        snapshotPath: ".areamatrix/diagnostics/database-repair-diagnostics.zip",
        createdAt: 1_778_000_000,
        warnings: ["paths redacted"]
    )
}

private extension CoreErrorMappingSnapshot {
    static func databaseRepairIntegrationMapping(
        kind: CoreErrorKindSnapshot,
        severity: CoreErrorSeveritySnapshot,
        recoverability: CoreErrorRecoverabilitySnapshot,
        rawContext: String
    ) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: kind,
            userMessage: "Repository metadata needs repair",
            severity: severity,
            suggestedAction: "Run a full metadata rescan after preserving diagnostics.",
            recoverability: recoverability,
            rawContext: rawContext
        )
    }
}

private func databaseRepairIntegrationTemporaryDirectory() throws -> URL {
    try makeTestTemporaryDirectory(named: "AreaMatrixDatabaseRepairIntegration")
}

private func databaseRepairIntegrationWriteRepoFile(
    _ repoURL: URL,
    relativePath: String,
    contents: String
) throws -> URL {
    let url = repoURL.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return url
}

private func databaseRepairIntegrationUserFileSnapshot(_ urls: [URL]) throws
    -> [UserFileSnapshot] {
    try urls.map { url in
        try UserFileSnapshot(path: url.path, data: Data(contentsOf: url))
    }
}
