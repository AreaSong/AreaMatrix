@testable import AreaMatrix
import Foundation
import XCTest

final class ImportProgressInterruptedSessionTests: XCTestCase {
    func testFileSessionStoreSavesAndLoadsSnapshotFromRepositoryMetadata() async throws {
        let repoURL = try makeTestTemporaryDirectory(named: "AreaMatrixImportSessionStore")
        defer { removeTestTemporaryItems(repoURL) }
        let store = FileImportBatchSessionStore()
        let session = importSessionFixture(repoURL: repoURL)

        try await store.saveSession(session)
        let loaded = try await store.loadSession(repoPath: repoURL.path)

        XCTAssertEqual(loaded, session)
        XCTAssertTrue(FileManager.default.fileExists(atPath: importSessionURL(repoURL: repoURL).path))
    }

    func testFileSessionStoreRoundTripsSourceRetainedCommitState() async throws {
        let repoURL = try makeTestTemporaryDirectory(named: "AreaMatrixImportSessionStore")
        defer { removeTestTemporaryItems(repoURL) }
        let store = FileImportBatchSessionStore()
        var session = importSessionFixture(repoURL: repoURL)
        session.items[0].importCommitState = .sourceRetained

        try await store.saveSession(session)
        let loaded = try await store.loadSession(repoPath: repoURL.path)

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

        let loaded = try await FileImportBatchSessionStore().loadSession(repoPath: repoURL.path)

        XCTAssertEqual(loaded?.items.first?.importCommitState, .committed)
    }

    func testFileSessionStoreReturnsNilForMissingMetadata() async throws {
        let repoURL = try makeTestTemporaryDirectory(named: "AreaMatrixImportSessionStore")
        defer { removeTestTemporaryItems(repoURL) }
        let store = FileImportBatchSessionStore()

        let missingSession = try await store.loadSession(repoPath: repoURL.path)
        XCTAssertNil(missingSession)
    }

    func testFileSessionStoreReportsCorruptedMetadata() async throws {
        let repoURL = try makeTestTemporaryDirectory(named: "AreaMatrixImportSessionStore")
        defer { removeTestTemporaryItems(repoURL) }
        let store = FileImportBatchSessionStore()

        let sessionURL = importSessionURL(repoURL: repoURL)
        try FileManager.default.createDirectory(
            at: sessionURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: sessionURL)

        do {
            _ = try await store.loadSession(repoPath: repoURL.path)
            XCTFail("Expected corrupted session metadata to throw")
        } catch let error as ImportBatchSessionStoreError {
            XCTAssertEqual(error, .corrupt)
        }
    }

    func testFileSessionStoreClearRemovesPersistedMetadataAndToleratesRepeatedClear() async throws {
        let repoURL = try makeTestTemporaryDirectory(named: "AreaMatrixImportSessionStore")
        defer { removeTestTemporaryItems(repoURL) }
        let store = FileImportBatchSessionStore()
        try await store.saveSession(importSessionFixture(repoURL: repoURL))

        try await store.clearSession(repoPath: repoURL.path)
        try await store.clearSession(repoPath: repoURL.path)

        XCTAssertFalse(FileManager.default.fileExists(atPath: importSessionURL(repoURL: repoURL).path))
        let clearedSession = try await store.loadSession(repoPath: repoURL.path)
        XCTAssertNil(clearedSession)
    }

    func testFileSessionStoreReportsWriteFailureWithoutCreatingMetadataOrEscapingRepository() async throws {
        let repoURL = try makeTestTemporaryDirectory(named: "AreaMatrixImportSessionStore")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: repoURL.path)
            removeTestTemporaryItems(repoURL)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: repoURL.path)
        let store = FileImportBatchSessionStore()

        do {
            try await store.saveSession(importSessionFixture(repoURL: repoURL))
            XCTFail("Expected permission error")
        } catch let error as ImportBatchSessionStoreError {
            XCTAssertEqual(error, .permission(operation: .save))
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: importSessionURL(repoURL: repoURL).path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: repoURL.path), [])
    }

    func testFileSessionStoreRejectsSymlinkedSessionDirectoryWithoutTouchingExternalSentinel() async throws {
        let repoURL = try makeTestTemporaryDirectory(named: "AreaMatrixImportSessionSymlink")
        let externalURL = try makeTestTemporaryDirectory(named: "AreaMatrixImportSessionExternal")
        defer {
            removeTestTemporaryItems(repoURL)
            removeTestTemporaryItems(externalURL)
        }

        let metadataURL = repoURL.appendingPathComponent(".areamatrix", isDirectory: true)
        let sessionsURL = metadataURL.appendingPathComponent("import-sessions", isDirectory: true)
        let sentinelURL = externalURL.appendingPathComponent("current.json")
        try FileManager.default.createDirectory(at: metadataURL, withIntermediateDirectories: true)
        try Data("external-sentinel".utf8).write(to: sentinelURL)
        try FileManager.default.createSymbolicLink(at: sessionsURL, withDestinationURL: externalURL)

        let store = FileImportBatchSessionStore()
        do {
            try await store.saveSession(importSessionFixture(repoURL: repoURL))
            XCTFail("Expected unsafe path error")
        } catch let error as ImportBatchSessionStoreError {
            XCTAssertEqual(error, .unsafePath(operation: .save))
        }
        do {
            try await store.clearSession(repoPath: repoURL.path)
            XCTFail("Expected unsafe path error")
        } catch let error as ImportBatchSessionStoreError {
            XCTAssertEqual(error, .unsafePath(operation: .clear))
        }

        XCTAssertEqual(try Data(contentsOf: sentinelURL), Data("external-sentinel".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionsURL.path))
    }

    func testFileSessionStoreRejectsSymlinkedRepositoryAncestor() async throws {
        let containerURL = try makeTestTemporaryDirectory(named: "AreaMatrixImportSessionAncestor")
        let externalURL = try makeTestTemporaryDirectory(named: "AreaMatrixImportSessionAncestorExternal")
        defer {
            removeTestTemporaryItems(containerURL)
            removeTestTemporaryItems(externalURL)
        }
        let aliasURL = containerURL.appendingPathComponent("linked-parent", isDirectory: true)
        let repoURL = externalURL.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: aliasURL, withDestinationURL: externalURL)

        do {
            try await FileImportBatchSessionStore().saveSession(
                importSessionFixture(repoURL: aliasURL.appendingPathComponent("repo", isDirectory: true))
            )
            XCTFail("Expected symlinked repository ancestor to be rejected")
        } catch let error as ImportBatchSessionStoreError {
            XCTAssertEqual(error, .unsafePath(operation: .save))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: importSessionURL(repoURL: repoURL).path))
    }

    func testFileSessionStoreRejectsFilesystemRootAsRepository() async {
        do {
            try await FileImportBatchSessionStore()
                .saveSession(importSessionFixture(repoURL: URL(fileURLWithPath: "/")))
            XCTFail("Expected filesystem root to be rejected")
        } catch let error as ImportBatchSessionStoreError {
            XCTAssertEqual(error, .unsafePath(operation: .save))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
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

    @MainActor
    func testInterruptedSessionLoadFailureKeepsMainRouteAndShowsRecoveryWarning() async {
        let opening = RepositoryOpeningResult.mainLoadingFixture(repoPath: importProgressRepoPath(), fileCount: 1)
        let failure = ImportBatchSessionStoreError.corrupt
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            startupRecoverer: StaticStartupRecoverer(),
            importBatchSessionStore: StaticImportBatchSessionStore(session: nil, loadFailure: failure),
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.finishSuccessfulRepositoryOpen(opening)
        let warning = await waitForToastMessage(model)

        XCTAssertEqual(model.route, .mainList(opening))
        XCTAssertEqual(warning, failure.userMessage)
    }

    @MainActor
    func testInterruptedSessionClearFailureKeepsResultVisibleForRetry() async {
        let opening = RepositoryOpeningResult.mainLoadingFixture(repoPath: importProgressRepoPath(), fileCount: 1)
        let failure = ImportBatchSessionStoreError.permission(operation: .clear)
        let store = StaticImportBatchSessionStore(
            session: ImportProgressFixtures.interruptedCopySessionOnePending,
            clearFailure: failure
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
        model.finishImportResult()
        let warning = await waitForToastMessage(model, excluding: L10n.message("import.interruptedSession.detected"))

        XCTAssertEqual(model.route, .importResult(result))
        XCTAssertEqual(warning, failure.userMessage)
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

@MainActor
private func waitForToastMessage(
    _ model: OnboardingModel,
    excluding ignoredMessage: LocalizedMessage? = nil,
    attempts: Int = 1000
) async -> LocalizedMessage? {
    for _ in 0 ..< attempts {
        if let message = model.toastMessage, message != ignoredMessage { return message }
        await Task.yield()
    }
    XCTFail("Timed out waiting for import session warning")
    return model.toastMessage
}
