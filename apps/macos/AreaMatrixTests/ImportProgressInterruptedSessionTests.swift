@testable import AreaMatrix
import Foundation
import XCTest

final class ImportProgressInterruptedSessionTests: XCTestCase {
    func testFileSessionStoreSavesAndLoadsSnapshotFromRepositoryMetadata() async throws {
        let repoURL = try makeTestTemporaryDirectory(named: "AreaMatrixImportSessionStore")
        defer { removeTestTemporaryItems(repoURL) }
        let store = FileImportBatchSessionStore()
        let session = importSessionFixture(repoURL: repoURL)

        await store.saveSession(session)
        let loaded = await store.loadSession(repoPath: repoURL.path)

        XCTAssertEqual(loaded, session)
        XCTAssertTrue(FileManager.default.fileExists(atPath: importSessionURL(repoURL: repoURL).path))
    }

    func testFileSessionStoreRoundTripsSourceRetainedCommitState() async throws {
        let repoURL = try makeTestTemporaryDirectory(named: "AreaMatrixImportSessionStore")
        defer { removeTestTemporaryItems(repoURL) }
        let store = FileImportBatchSessionStore()
        var session = importSessionFixture(repoURL: repoURL)
        session.items[0].importCommitState = .sourceRetained

        await store.saveSession(session)
        let loaded = await store.loadSession(repoPath: repoURL.path)

        XCTAssertEqual(loaded, session)
        XCTAssertEqual(loaded?.items.first?.importCommitState, .sourceRetained)
    }

    func testFileSessionStoreDefaultsLegacyItemsToCommitted() async throws {
        let repoURL = try makeTestTemporaryDirectory(named: "AreaMatrixImportSessionStore")
        defer { removeTestTemporaryItems(repoURL) }
        let sessionURL = importSessionURL(repoURL: repoURL)
        try FileManager.default.createDirectory(
            at: sessionURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let legacyJSON = """
        {
          "repoPath": "\(repoURL.path)",
          "storageMode": "Copy",
          "completed": 1,
          "failed": 0,
          "total": 1,
          "currentPath": "docs/source.pdf",
          "items": [
            {
              "sourcePath": "/tmp/source.pdf",
              "targetPath": "docs/source.pdf",
              "phase": "Done"
            }
          ]
        }
        """
        try Data(legacyJSON.utf8).write(to: sessionURL)

        let loaded = await FileImportBatchSessionStore().loadSession(repoPath: repoURL.path)

        XCTAssertEqual(loaded?.items.first?.importCommitState, .committed)
    }

    func testFileSessionStoreReturnsNilForMissingOrCorruptedMetadata() async throws {
        let repoURL = try makeTestTemporaryDirectory(named: "AreaMatrixImportSessionStore")
        defer { removeTestTemporaryItems(repoURL) }
        let store = FileImportBatchSessionStore()

        let missingSession = await store.loadSession(repoPath: repoURL.path)
        XCTAssertNil(missingSession)

        let sessionURL = importSessionURL(repoURL: repoURL)
        try FileManager.default.createDirectory(
            at: sessionURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: sessionURL)

        let corruptedSession = await store.loadSession(repoPath: repoURL.path)
        XCTAssertNil(corruptedSession)
    }

    func testFileSessionStoreClearRemovesPersistedMetadataAndToleratesRepeatedClear() async throws {
        let repoURL = try makeTestTemporaryDirectory(named: "AreaMatrixImportSessionStore")
        defer { removeTestTemporaryItems(repoURL) }
        let store = FileImportBatchSessionStore()
        await store.saveSession(importSessionFixture(repoURL: repoURL))

        await store.clearSession(repoPath: repoURL.path)
        await store.clearSession(repoPath: repoURL.path)

        XCTAssertFalse(FileManager.default.fileExists(atPath: importSessionURL(repoURL: repoURL).path))
        let clearedSession = await store.loadSession(repoPath: repoURL.path)
        XCTAssertNil(clearedSession)
    }

    func testFileSessionStoreWriteFailureDoesNotCreateMetadataOrEscapeRepository() async throws {
        let repoURL = try makeTestTemporaryDirectory(named: "AreaMatrixImportSessionStore")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: repoURL.path)
            removeTestTemporaryItems(repoURL)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: repoURL.path)
        let store = FileImportBatchSessionStore()

        await store.saveSession(importSessionFixture(repoURL: repoURL))

        XCTAssertFalse(FileManager.default.fileExists(atPath: importSessionURL(repoURL: repoURL).path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: repoURL.path), [])
    }

    @MainActor
    func testInterruptedCopySessionRoutesToImportResultAfterRepositoryOpen() async {
        let opening = RepositoryOpeningResult.mainLoadingFixture(repoPath: importProgressRepoPath(), fileCount: 1)
        let store = StaticImportBatchSessionStore(
            session: ImportProgressFixtures.interruptedCopySessionTwoPending
        )
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            startupRecoverer: StaticStartupRecoverer(),
            importBatchSessionStore: store,
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.finishSuccessfulRepositoryOpen(opening)
        guard let result = await waitForImportResultRoute(model) else { return }

        assertImportResultSummary(
            result,
            summaryText: "Imported 1, failed 0, stopped 0, pending 2.",
            statuses: [.imported, .pending, .pending]
        )
        XCTAssertEqual(result.items.dropFirst().map(\.reason), [
            "Import not completed before AreaMatrix quit",
            "Import not completed before AreaMatrix quit"
        ])
        XCTAssertEqual(
            model.toastMessage,
            L10n.message("import.interruptedSession.detected")
        )
    }

    @MainActor
    func testInterruptedCopySessionIsClearedWhenUserAcknowledgesResults() async {
        let opening = RepositoryOpeningResult.mainLoadingFixture(repoPath: importProgressRepoPath(), fileCount: 1)
        let store = StaticImportBatchSessionStore(
            session: ImportProgressFixtures.interruptedCopySessionOnePending
        )
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            startupRecoverer: StaticStartupRecoverer(),
            importBatchSessionStore: store,
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.finishSuccessfulRepositoryOpen(opening)
        guard await waitForImportResultRoute(model) != nil else { return }
        model.finishImportResult()
        let mainListOpening = await waitForMainListRoute(model)

        let clearedRepoPaths = await store.waitForClearedRepoPaths([importProgressRepoPath()])
        XCTAssertEqual(clearedRepoPaths, [importProgressRepoPath()])
        XCTAssertEqual(mainListOpening, opening)
    }

    @MainActor
    func testCorruptedOrMissingInterruptedCopySessionDoesNotBlockMainRoute() async {
        let opening = RepositoryOpeningResult.mainLoadingFixture(repoPath: importProgressRepoPath(), fileCount: 1)
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            startupRecoverer: StaticStartupRecoverer(),
            importBatchSessionStore: StaticImportBatchSessionStore(session: nil),
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.finishSuccessfulRepositoryOpen(opening)
        let mainListOpening = await waitForMainListRoute(model)

        XCTAssertEqual(mainListOpening, opening)
        XCTAssertNil(model.toastMessage)
    }

    private func importSessionFixture(repoURL: URL) -> ImportBatchSessionSnapshot {
        ImportBatchSessionSnapshot.testFixture {
            $0.repoPath = repoURL.path
            $0.total = 3
            $0.items = ImportProgressFixtures.interruptedCopySessionTwoPending.items
        }
    }

    private func importSessionURL(repoURL: URL) -> URL {
        repoURL
            .appendingPathComponent(".areamatrix", isDirectory: true)
            .appendingPathComponent("import-sessions", isDirectory: true)
            .appendingPathComponent("current.json")
    }
}
