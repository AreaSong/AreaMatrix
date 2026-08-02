@testable import AreaMatrix
import XCTest

final class RepoSettingsPageIntegrationTests: XCTestCase {
    @MainActor
    func testRepositorySettingsCrossPlatformPageIntegrationConnectsCoreConfigCapabilitiesAndSafeActions() async throws {
        let context = try await makeRepositorySettingsIntegrationContext()
        defer {
            removeTestTemporaryItems(context.repoURL, context.sourceRootURL)
        }

        await context.model.load()
        context.model.revealRepositoryInFinder()
        context.model.copyRepositoryPath()
        context.model.requestDiagnosticsExport()
        await context.model.collectDiagnostics()

        await assertRepositorySettingsIntegrationState(context: context)
    }

    @MainActor
    func testRepositorySettingsChangeRepositoryCancelReturnsToRepositorySettingsWithoutSavingCandidate() {
        let opening = RepositoryOpeningResult.shellFixture(repoPath: "/tmp/current-repo", fileCount: 1)
        let writer = ShellRecordingSettingsWriter()
        let fixture = makeShellSettingsGeneralFixture(
            opening: opening,
            selectedTab: "repository",
            model: makeShellOnboardingModel(
                settingsReader: ShellStaticSettingsReader(repoPath: nil),
                settingsWriter: writer,
                accessibilityAnnouncer: RecordingAccessibilityAnnouncer()
            )
        )
        let model = fixture.model

        model.beginSettingsRepositoryChange(from: opening)
        model.updateRepositoryPath("/tmp/candidate-repo")
        model.returnFromChoosePath()

        XCTAssertEqual(model.route, .settingsGeneral(opening))
        XCTAssertEqual(model.settingsGeneralSelectedTab, "repository")
        writer.assertNoSavedRepoPaths()
    }

    @MainActor
    func testRepositorySettingsChangeRepositoryOpensCandidateOnlyAfterValidationAndCoreOpen() async {
        let currentOpening = RepositoryOpeningResult.shellFixture(repoPath: "/tmp/current-repo", fileCount: 1)
        let newOpening = RepositoryOpeningResult.shellFixture(repoPath: "/tmp/new-repo", fileCount: 2)
        let validation = RepoPathValidationSnapshot.shellFixture(
            repoPath: "/tmp/new-repo",
            isEmpty: false,
            isInitialized: true,
            issues: [.alreadyInitialized, .nonEmptyDirectory],
            recommendedMode: nil
        )
        let validator = ShellRecordingPathValidator(result: .success(validation))
        let opener = ShellRecordingRepositoryOpener(result: .success(newOpening))
        let writer = ShellRecordingSettingsWriter()
        let fixture = makeShellSettingsGeneralFixture(
            opening: currentOpening,
            selectedTab: "repository",
            model: makeShellOnboardingModel(
                settingsReader: ShellStaticSettingsReader(repoPath: "/tmp/current-repo"),
                settingsWriter: writer,
                pathValidator: validator,
                emptyRepositoryOpener: opener,
                existingRepositoryMetadataReader: ShellExistingRepoMetadataReader(
                    schemaVersion: 1,
                    configuredRepoPath: "/tmp/new-repo"
                ),
                scanSessionReader: RepoSettingsScanSessionReader(result: .success(nil)),
                accessibilityAnnouncer: RecordingAccessibilityAnnouncer()
            )
        )
        let model = fixture.model

        model.beginSettingsRepositoryChange(from: currentOpening)
        model.updateRepositoryPath("/tmp/new-repo")
        await model.continueFromChoosePath()
        await model.continueFromValidatePath()

        await validator.assertRequestedRepoPaths(["/tmp/new-repo"])
        await opener.assertRequestedConfiguredRepoPaths(["/tmp/new-repo"])
        writer.assertSavedRepoPaths(["/tmp/new-repo"])
        XCTAssertEqual(model.route, .mainList(newOpening))
    }
}

private struct RepositorySettingsIntegrationContext {
    let repoURL: URL
    let sourceRootURL: URL
    let sourceURL: URL
    let imported: FileEntrySnapshot
    let diagnosticsSnapshot: DiagnosticsSnapshotSnapshot
    let finder: RecordingRepositoryFinderOpener
    let copier: ShellRecordingPathCopier
    let diagnostics: ShellRecordingDiagnosticsCollector
    let announcer: RecordingAccessibilityAnnouncer
    let model: RepositorySettingsModel
}

private struct RepositorySettingsIntegrationURLs {
    let repoURL: URL
    let sourceRootURL: URL
    let sourceURL: URL
}

private struct RepositorySettingsIntegrationDoubles {
    let finder: RecordingRepositoryFinderOpener
    let copier: ShellRecordingPathCopier
    let diagnostics: ShellRecordingDiagnosticsCollector
    let announcer: RecordingAccessibilityAnnouncer
}

@MainActor
private func makeRepositorySettingsIntegrationContext() async throws -> RepositorySettingsIntegrationContext {
    let urls = try makeRepositorySettingsIntegrationURLs()
    var cleanupURLs = [urls.repoURL, urls.sourceRootURL]
    var didSucceed = false
    defer {
        if !didSucceed {
            removeTestTemporaryItems(cleanupURLs)
        }
    }

    let bridge = CoreBridge()
    try await bridge.initializeEmptyRepository(repoPath: urls.repoURL.path)
    let imported = try await bridge.importIndexedFile(
        repoPath: urls.repoURL.path,
        sourceURL: urls.sourceURL,
        overrideCategory: "docs",
        overrideFilename: "indexed-display.pdf"
    )
    let diagnosticsSnapshot = makeRepositorySettingsDiagnosticsSnapshot(repoURL: urls.repoURL)
    let doubles = makeRepositorySettingsIntegrationDoubles(diagnosticsSnapshot: diagnosticsSnapshot)
    let model = makeRepositorySettingsModel(urls: urls, bridge: bridge, doubles: doubles)

    let context = RepositorySettingsIntegrationContext(
        repoURL: urls.repoURL,
        sourceRootURL: urls.sourceRootURL,
        sourceURL: urls.sourceURL,
        imported: imported,
        diagnosticsSnapshot: diagnosticsSnapshot,
        finder: doubles.finder,
        copier: doubles.copier,
        diagnostics: doubles.diagnostics,
        announcer: doubles.announcer,
        model: model
    )
    didSucceed = true
    return context
}

private func makeRepositorySettingsIntegrationURLs() throws -> RepositorySettingsIntegrationURLs {
    let repoURL = try temporaryRepositorySettingsRepo()
    let sourceRootURL = try temporaryRepositorySettingsRepo()
    let sourceURL = sourceRootURL.appendingPathComponent("indexed.pdf")
    try Data("indexed bytes".utf8).write(to: sourceURL)
    return RepositorySettingsIntegrationURLs(
        repoURL: repoURL,
        sourceRootURL: sourceRootURL,
        sourceURL: sourceURL
    )
}

private func makeRepositorySettingsDiagnosticsSnapshot(repoURL: URL) -> DiagnosticsSnapshotSnapshot {
    DiagnosticsSnapshotSnapshot.testFixture(
        snapshotPath: repoURL
            .appendingPathComponent(".areamatrix", isDirectory: true)
            .appendingPathComponent("diagnostics", isDirectory: true)
            .appendingPathComponent("repository-settings-diagnostics.zip")
            .path,
        createdAt: 1_778_000_000
    )
}

@MainActor
private func makeRepositorySettingsIntegrationDoubles(
    diagnosticsSnapshot: DiagnosticsSnapshotSnapshot
) -> RepositorySettingsIntegrationDoubles {
    RepositorySettingsIntegrationDoubles(
        finder: RecordingRepositoryFinderOpener(),
        copier: ShellRecordingPathCopier(),
        diagnostics: ShellRecordingDiagnosticsCollector(result: .success(diagnosticsSnapshot)),
        announcer: RecordingAccessibilityAnnouncer()
    )
}

@MainActor
private func makeRepositorySettingsModel(
    urls: RepositorySettingsIntegrationURLs,
    bridge: CoreBridge,
    doubles: RepositorySettingsIntegrationDoubles
) -> RepositorySettingsModel {
    RepositorySettingsModel(
        repoPath: urls.repoURL.path,
        loader: bridge,
        updater: bridge,
        repositoryOpener: bridge,
        fileLister: bridge,
        scanSessionReader: bridge,
        existingRepositoryMetadataReader: SQLiteExistingRepositoryMetadataReader(),
        finderOpener: doubles.finder,
        pathCopier: doubles.copier,
        diagnosticsCollector: doubles.diagnostics,
        coreVersionLoader: bridge,
        errorMapper: bridge,
        accessibilityAnnouncer: doubles.announcer
    )
}

@MainActor
private func assertRepositorySettingsIntegrationState(context: RepositorySettingsIntegrationContext) async {
    let summary = context.model.summary
    let healthSummary = context.model.healthSummary
    let repositoryActionError = context.model.repositoryActionError
    let diagnosticsState = context.model.diagnosticsState

    XCTAssertEqual(context.imported.storageMode, "Indexed")
    XCTAssertEqual(context.imported.sourcePath, context.sourceURL.path)
    XCTAssertTrue(FileManager.default.fileExists(atPath: context.sourceURL.path))
    XCTAssertFalse(FileManager.default.fileExists(
        atPath: context.repoURL.appendingPathComponent(context.imported.path).path
    ))
    XCTAssertFalse(FileManager.default.fileExists(atPath: context.repoURL.appendingPathComponent("README.md").path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: context.repoURL.appendingPathComponent("AREAMATRIX.md").path))

    XCTAssertEqual(summary?.location, context.repoURL.path)
    XCTAssertEqual(summary?.locationType, "Local folder")
    XCTAssertEqual(summary?.metadataStatus, ".areamatrix/ found")
    XCTAssertEqual(summary?.coreVersion, "0.1.0")
    XCTAssertEqual(healthSummary?.databaseStatus, .ok)
    XCTAssertEqual(healthSummary?.schemaVersion, 3)
    XCTAssertEqual(healthSummary?.filesIndexed, 1)
    XCTAssertNil(repositoryActionError)
    XCTAssertEqual(diagnosticsState, .collected(context.diagnosticsSnapshot))
    context.finder.assertRepoPaths([context.repoURL.path])
    context.copier.assertCopiedPathRequests([ShellRecordingPathCopier.Request(
        repoPath: context.repoURL.path,
        relativePath: ""
    )])
    await context.diagnostics.assertRequestedRepoPaths([context.repoURL.path])
    context.announcer.assertAnnouncements(["Repository path copied."])
}
