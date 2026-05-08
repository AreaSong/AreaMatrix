import XCTest
@testable import AreaMatrix

final class RepositorySettingsPageIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testS127PageIntegrationConnectsCoreConfigIndexedCountOverviewAndSafeActions() async throws {
        let context = try await makeRepositorySettingsIntegrationContext()
        defer {
            try? FileManager.default.removeItem(at: context.repoURL)
            try? FileManager.default.removeItem(at: context.sourceRootURL)
        }

        await context.model.load()
        context.model.revealRepositoryInFinder()
        context.model.copyRepositoryPath()
        context.model.revealGeneratedOverviewInFinder()
        let generatedOverviewActionMessage = context.model.repositoryActionMessage
        context.model.requestDiagnosticsExport()
        await context.model.collectDiagnostics()
        let diagnosticsRepoPaths = await context.diagnostics.requestedRepoPaths()

        assertRepositorySettingsIntegrationState(
            context: context,
            diagnosticsRepoPaths: diagnosticsRepoPaths,
            generatedOverviewActionMessage: generatedOverviewActionMessage
        )
    }

    @MainActor
    func testS127ChangeRepositoryCancelReturnsToRepositorySettingsWithoutSavingCandidate() {
        let opening = RepositoryOpeningResult.shellFixture(repoPath: "/tmp/current-repo", fileCount: 1)
        let writer = ShellRecordingSettingsWriter()
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            settingsWriter: writer,
            accessibilityAnnouncer: S117RecordingAccessibilityAnnouncer(),
            helpOpener: S117NoopWelcomeHelpOpener()
        )

        model.route = .settingsGeneral(opening)
        model.settingsGeneralSelectedTab = "repository"
        model.beginSettingsRepositoryChange(from: opening)
        model.updateRepositoryPath("/tmp/candidate-repo")
        model.returnFromChoosePath()

        XCTAssertEqual(model.route, .settingsGeneral(opening))
        XCTAssertEqual(model.settingsGeneralSelectedTab, "repository")
        XCTAssertEqual(writer.savedRepoPaths, [])
    }

    @MainActor
    func testS127ChangeRepositoryOpensCandidateOnlyAfterValidationAndCoreOpen() async {
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
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: "/tmp/current-repo"),
            settingsWriter: writer,
            pathValidator: validator,
            emptyRepositoryOpener: opener,
            startupRecoverer: ShellStaticStartupRecoverer(),
            existingRepositoryMetadataReader: ShellStaticExistingRepositoryMetadataReader(
                schemaVersion: 1,
                configuredRepoPath: "/tmp/new-repo"
            ),
            scanSessionReader: RepositorySettingsRecordingScanSessionReader(result: .success(nil)),
            accessibilityAnnouncer: S117RecordingAccessibilityAnnouncer(),
            helpOpener: S117NoopWelcomeHelpOpener()
        )

        model.route = .settingsGeneral(currentOpening)
        model.settingsGeneralSelectedTab = "repository"
        model.beginSettingsRepositoryChange(from: currentOpening)
        model.updateRepositoryPath("/tmp/new-repo")
        await model.continueFromChoosePath()
        await model.continueFromValidatePath()
        let validatedPaths = await validator.requestedRepoPaths()
        let openedPaths = await opener.requestedConfiguredRepoPaths()

        XCTAssertEqual(validatedPaths, ["/tmp/new-repo"])
        XCTAssertEqual(openedPaths, ["/tmp/new-repo"])
        XCTAssertEqual(writer.savedRepoPaths, ["/tmp/new-repo"])
        XCTAssertEqual(model.route, .mainList(newOpening))
    }
}

private struct RepositorySettingsIntegrationContext {
    let repoURL: URL
    let sourceRootURL: URL
    let sourceURL: URL
    let imported: FileEntrySnapshot
    let generatedURL: URL
    let diagnosticsSnapshot: DiagnosticsSnapshotSnapshot
    let finder: ShellRecordingFinderOpener
    let copier: ShellRecordingPathCopier
    let generatedRevealer: RepositorySettingsRecordingFileRevealer
    let diagnostics: ShellRecordingDiagnosticsCollector
    let announcer: S117RecordingAccessibilityAnnouncer
    let model: RepositorySettingsModel
}

@MainActor
private func makeRepositorySettingsIntegrationContext() async throws -> RepositorySettingsIntegrationContext {
    let repoURL = try temporaryRepositorySettingsRepo()
    var cleanupURLs = [repoURL]
    var didSucceed = false
    defer {
        if !didSucceed {
            cleanupURLs.forEach { try? FileManager.default.removeItem(at: $0) }
        }
    }
    let sourceRoot = try temporaryRepositorySettingsRepo()
    cleanupURLs.append(sourceRoot)

    let sourceURL = sourceRoot.appendingPathComponent("indexed.pdf")
    try Data("indexed bytes".utf8).write(to: sourceURL)
    let bridge = CoreBridge()
    try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
    let imported = try await bridge.importIndexedFile(
        repoPath: repoURL.path,
        sourceURL: sourceURL,
        overrideCategory: "docs",
        overrideFilename: "indexed-display.pdf"
    )
    let generatedURL = repoURL
        .appendingPathComponent(".areamatrix", isDirectory: true)
        .appendingPathComponent("generated", isDirectory: true)
        .appendingPathComponent("root.md", isDirectory: false)
    let diagnosticsSnapshot = DiagnosticsSnapshotSnapshot(
        snapshotPath: repoURL
            .appendingPathComponent(".areamatrix", isDirectory: true)
            .appendingPathComponent("diagnostics", isDirectory: true)
            .appendingPathComponent("s1-27.zip")
            .path,
        createdAt: 1_778_000_000,
        warnings: []
    )
    let finder = ShellRecordingFinderOpener()
    let copier = ShellRecordingPathCopier()
    let generatedRevealer = RepositorySettingsRecordingFileRevealer()
    let diagnostics = ShellRecordingDiagnosticsCollector(result: .success(diagnosticsSnapshot))
    let announcer = S117RecordingAccessibilityAnnouncer()
    let model = RepositorySettingsModel(
        repoPath: repoURL.path,
        loader: bridge,
        updater: bridge,
        repositoryOpener: bridge,
        fileLister: bridge,
        scanSessionReader: bridge,
        existingRepositoryMetadataReader: SQLiteExistingRepositoryMetadataReader(),
        finderOpener: finder,
        pathCopier: copier,
        generatedOverviewRevealer: generatedRevealer,
        diagnosticsCollector: diagnostics,
        errorMapper: bridge,
        accessibilityAnnouncer: announcer
    )

    let context = RepositorySettingsIntegrationContext(
        repoURL: repoURL,
        sourceRootURL: sourceRoot,
        sourceURL: sourceURL,
        imported: imported,
        generatedURL: generatedURL,
        diagnosticsSnapshot: diagnosticsSnapshot,
        finder: finder,
        copier: copier,
        generatedRevealer: generatedRevealer,
        diagnostics: diagnostics,
        announcer: announcer,
        model: model
    )
    didSucceed = true
    return context
}

@MainActor
private func assertRepositorySettingsIntegrationState(
    context: RepositorySettingsIntegrationContext,
    diagnosticsRepoPaths: [String],
    generatedOverviewActionMessage: String?
) {
    let summary = context.model.summary
    let healthSummary = context.model.healthSummary
    let repositoryActionError = context.model.repositoryActionError
    let overviewActionError = context.model.overviewActionError
    let diagnosticsState = context.model.diagnosticsState
    let openedRepoPaths = context.finder.openedRepoPaths
    let copyRequests = context.copier.requests
    let generatedRequests = context.generatedRevealer.requests
    let announcements = context.announcer.announcements

    XCTAssertEqual(context.imported.storageMode, "Indexed")
    XCTAssertEqual(context.imported.sourcePath, context.sourceURL.path)
    XCTAssertTrue(FileManager.default.fileExists(atPath: context.sourceURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: context.repoURL.appendingPathComponent(context.imported.path).path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: context.generatedURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: context.repoURL.appendingPathComponent("README.md").path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: context.repoURL.appendingPathComponent("AREAMATRIX.md").path))

    XCTAssertEqual(summary?.location, context.repoURL.path)
    XCTAssertEqual(summary?.metadataStatus, ".areamatrix/ found")
    XCTAssertEqual(summary?.overviewMode, "Generated only")
    XCTAssertEqual(summary?.generatedPath, ".areamatrix/generated/root.md")
    XCTAssertEqual(summary?.rootFile, "Off")
    XCTAssertEqual(summary?.readmePolicy, "User file, never managed by AreaMatrix")
    XCTAssertEqual(healthSummary?.databaseStatus, .ok)
    XCTAssertEqual(healthSummary?.schemaVersion, 1)
    XCTAssertEqual(healthSummary?.filesIndexed, 1)
    XCTAssertEqual(generatedOverviewActionMessage, "Generated overview revealed in Finder.")
    XCTAssertNil(repositoryActionError)
    XCTAssertNil(overviewActionError)
    XCTAssertEqual(diagnosticsState, .collected(context.diagnosticsSnapshot))
    XCTAssertEqual(openedRepoPaths, [context.repoURL.path])
    XCTAssertEqual(copyRequests.map { $0.repoPath }, [context.repoURL.path])
    XCTAssertEqual(copyRequests.map { $0.relativePath }, [""])
    XCTAssertEqual(generatedRequests, [RepositorySettingsRecordingFileRevealer.Request(
        repoPath: context.repoURL.path,
        relativePath: RepositorySettingsSummary.generatedOverviewRelativePath
    )])
    XCTAssertEqual(diagnosticsRepoPaths, [context.repoURL.path])
    XCTAssertEqual(announcements, ["Repository path copied."])
}
