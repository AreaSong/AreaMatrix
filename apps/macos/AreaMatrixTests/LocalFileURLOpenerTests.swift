@testable import AreaMatrix
import Foundation
import XCTest

final class LocalFileURLOpenerTests: XCTestCase {
    @MainActor
    func testLocalFileURLOpenerOpensExistingURL() throws {
        let url = URL(fileURLWithPath: "/tmp/areamatrix-file.txt")
        let resourceReader = RecordingLocalFileURLResourceReader(snapshot: .init(exists: true, isDirectory: false))
        let platformOpener = RecordingLocalFileURLPlatformOpener()
        let opener = NSWorkspaceLocalFileURLOpener(resourceReader: resourceReader, platformOpener: platformOpener)

        try opener.openExisting(url, requiresDirectory: false)

        resourceReader.assertRequestedPaths([url.path])
        platformOpener.assertOpenedPaths([url.path])
        platformOpener.assertNoRevealedURLs()
    }

    @MainActor
    func testLocalFileURLOpenerRejectsMissingURLBeforeOpen() {
        let url = URL(fileURLWithPath: "/tmp/missing.txt")
        let resourceReader = RecordingLocalFileURLResourceReader(snapshot: .init(exists: false, isDirectory: false))
        let platformOpener = RecordingLocalFileURLPlatformOpener()
        let opener = NSWorkspaceLocalFileURLOpener(resourceReader: resourceReader, platformOpener: platformOpener)

        XCTAssertThrowsError(try opener.openExisting(url, requiresDirectory: false)) { error in
            XCTAssertEqual(error as? LocalFileURLOpenError, .missing(url.path))
        }
        platformOpener.assertNoOpenedURLs()
        platformOpener.assertNoRevealedURLs()
    }

    @MainActor
    func testLocalFileURLOpenerRejectsNonDirectoryWhenRequired() {
        let url = URL(fileURLWithPath: "/tmp/not-directory.txt")
        let resourceReader = RecordingLocalFileURLResourceReader(snapshot: .init(exists: true, isDirectory: false))
        let platformOpener = RecordingLocalFileURLPlatformOpener()
        let opener = NSWorkspaceLocalFileURLOpener(resourceReader: resourceReader, platformOpener: platformOpener)

        XCTAssertThrowsError(try opener.openExisting(url, requiresDirectory: true)) { error in
            XCTAssertEqual(error as? LocalFileURLOpenError, .notDirectory(url.path))
        }
        platformOpener.assertNoOpenedURLs()
        platformOpener.assertNoRevealedURLs()
    }

    @MainActor
    func testLocalFileURLOpenerMapsRejectedOpen() {
        let url = URL(fileURLWithPath: "/tmp/rejected.txt")
        let resourceReader = RecordingLocalFileURLResourceReader(snapshot: .init(exists: true, isDirectory: false))
        let platformOpener = RecordingLocalFileURLPlatformOpener(openResult: false)
        let opener = NSWorkspaceLocalFileURLOpener(resourceReader: resourceReader, platformOpener: platformOpener)

        XCTAssertThrowsError(try opener.openExisting(url, requiresDirectory: false)) { error in
            XCTAssertEqual(error as? LocalFileURLOpenError, .openRejected(url.path))
        }
        platformOpener.assertOpenedPaths([url.path])
        platformOpener.assertNoRevealedURLs()
    }

    @MainActor
    func testLocalFileURLOpenerRevealsExistingURL() throws {
        let url = URL(fileURLWithPath: "/tmp/reveal.txt")
        let resourceReader = RecordingLocalFileURLResourceReader(snapshot: .init(exists: true, isDirectory: false))
        let platformOpener = RecordingLocalFileURLPlatformOpener()
        let opener = NSWorkspaceLocalFileURLOpener(resourceReader: resourceReader, platformOpener: platformOpener)

        try opener.revealExisting(url)

        resourceReader.assertRequestedPaths([url.path])
        platformOpener.assertNoOpenedURLs()
        platformOpener.assertRevealedPathGroups([[url.path]])
    }

    @MainActor
    func testRepositoryOpenersPreserveLocalFileURLErrorMapping() throws {
        let repoPath = "/tmp/repo"

        XCTAssertThrowsError(try NSWorkspaceRepositoryFinderOpener(
            localURLOpener: RecordingLocalFileURLOpener(result: .failure(LocalFileURLOpenError.missing(repoPath)))
        ).openRepositoryInFinder(repoPath: repoPath)) { error in
            XCTAssertEqual(error as? RepositoryFinderOpenError, .repositoryFolderMissing(repoPath))
        }

        XCTAssertThrowsError(try NSWorkspaceRepositoryFinderOpener(
            localURLOpener: RecordingLocalFileURLOpener(result: .failure(LocalFileURLOpenError.openRejected(repoPath)))
        ).openRepositoryInFinder(repoPath: repoPath)) { error in
            XCTAssertEqual(error as? RepositoryFinderOpenError, .openRejected(repoPath))
        }

        let fileOpener = RecordingLocalFileURLOpener()
        try NSWorkspaceRepositoryFileOpener(localURLOpener: fileOpener)
            .openFile(repoPath: repoPath, relativePath: "docs/a.pdf")
        fileOpener.assertOpenExistingRequests([(path: "/tmp/repo/docs/a.pdf", requiresDirectory: false)])

        let revealer = RecordingLocalFileURLOpener()
        try NSWorkspaceRepositoryFileRevealer(localURLOpener: revealer)
            .revealFile(repoPath: repoPath, relativePath: "docs/a.pdf")
        revealer.assertRevealExistingPaths(["/tmp/repo/docs/a.pdf"])
    }

    @MainActor
    func testLocalModelFolderOpenerUsesSharedLocalFileURLOpenerAndPreservesErrors() throws {
        XCTAssertThrowsError(try NSWorkspaceLocalModelFolderOpener(
            localURLOpener: RecordingLocalFileURLOpener(result: .failure(LocalFileURLOpenError.missing("/tmp/models")))
        ).openLocalModelFolder(localModelFolderLocation(folderPath: "/tmp/models"))) { error in
            XCTAssertEqual(error as? LocalModelStatusActionError, .openRejected)
        }
    }

    @MainActor
    func testWelcomeHelpOpenerUsesStableHTTPSUserGuideAndPreservesErrors() throws {
        let welcomeHelpOpener = RecordingExternalURLStringOpener()
        try WelcomeHelpOpener(externalURLOpener: welcomeHelpOpener).openWelcomeHelp()
        welcomeHelpOpener.assertOpenedValues([WelcomeHelpOpener.userGuideURL])

        XCTAssertThrowsError(try WelcomeHelpOpener(
            externalURLOpener: RecordingExternalURLStringOpener(
                result: .failure(ExternalURLOpenError.openRejected(WelcomeHelpOpener.userGuideURL))
            )
        ).openWelcomeHelp()) { error in
            XCTAssertEqual(error as? WelcomeHelpError, .helpDocumentUnavailable)
        }
    }

    @MainActor
    func testIgnoreRulesOpenerUsesSharedLocalFileURLOpenerForExistingFile() throws {
        let fixture = try makeIgnoreRulesFixture(includeIgnoreRulesFile: true)
        defer { removeTestTemporaryItems(fixture.repoURL) }

        let localURLOpener = RecordingLocalFileURLOpener()
        try NSWorkspaceRepositoryIgnoreRulesManager(localURLOpener: localURLOpener)
            .openIgnoreRules(repoPath: fixture.repoURL.path)

        localURLOpener.assertOpenedPaths([fixture.ignoreRulesURL.path])
        localURLOpener.assertNoOpenExistingRequests()
        localURLOpener.assertNoRevealExistingURLs()
    }

    @MainActor
    func testIgnoreRulesOpenerMapsSharedLocalFileURLOpenerFailureToOpenRejected() throws {
        let fixture = try makeIgnoreRulesFixture(includeIgnoreRulesFile: true)
        defer { removeTestTemporaryItems(fixture.repoURL) }

        let localURLOpener = RecordingLocalFileURLOpener(
            result: .failure(LocalFileURLOpenError.openRejected(fixture.ignoreRulesURL.path))
        )

        XCTAssertThrowsError(try NSWorkspaceRepositoryIgnoreRulesManager(localURLOpener: localURLOpener)
            .openIgnoreRules(repoPath: fixture.repoURL.path)) { error in
                XCTAssertEqual(error as? RepositoryIgnoreRulesError, .openRejected)
            }
        localURLOpener.assertOpenedPaths([fixture.ignoreRulesURL.path])
    }

    @MainActor
    func testIgnoreRulesOpenerRejectsMissingIgnoreRulesBeforeOpening() throws {
        let fixture = try makeIgnoreRulesFixture(includeIgnoreRulesFile: false)
        defer { removeTestTemporaryItems(fixture.repoURL) }

        let localURLOpener = RecordingLocalFileURLOpener()

        XCTAssertThrowsError(try NSWorkspaceRepositoryIgnoreRulesManager(localURLOpener: localURLOpener)
            .openIgnoreRules(repoPath: fixture.repoURL.path)) { error in
                XCTAssertEqual(error as? RepositoryIgnoreRulesError, .ignoreRulesMissing)
            }
        localURLOpener.assertNoOpenedURLs()
    }

    @MainActor
    func testIgnoreRulesOpenerRejectsNonRegularIgnoreRulesBeforeOpening() throws {
        let fixture = try makeIgnoreRulesFixture(includeIgnoreRulesFile: false)
        defer { removeTestTemporaryItems(fixture.repoURL) }
        try FileManager.default.createDirectory(at: fixture.ignoreRulesURL, withIntermediateDirectories: false)

        let localURLOpener = RecordingLocalFileURLOpener()

        XCTAssertThrowsError(try NSWorkspaceRepositoryIgnoreRulesManager(localURLOpener: localURLOpener)
            .openIgnoreRules(repoPath: fixture.repoURL.path)) { error in
                XCTAssertEqual(error as? RepositoryIgnoreRulesError, .ignoreRulesNotRegularFile)
            }
        localURLOpener.assertNoOpenedURLs()
    }
}

private func localModelFolderLocation(folderPath: String) -> LocalModelFolderLocationState {
    LocalModelFolderLocationState(
        modelID: "areamatrix-local",
        folderPath: folderPath,
        exists: true,
        readable: true,
        openable: true,
        unavailableReason: nil
    )
}

private func makeIgnoreRulesFixture(includeIgnoreRulesFile: Bool) throws -> (
    repoURL: URL,
    ignoreRulesURL: URL
) {
    let repoURL = try makeTestTemporaryDirectory(named: "AreaMatrixIgnoreRulesOpener")
    let metadataURL = repoURL.appendingPathComponent(".areamatrix", isDirectory: true)
    let ignoreRulesURL = metadataURL.appendingPathComponent("ignore.yaml")

    try FileManager.default.createDirectory(at: metadataURL, withIntermediateDirectories: true)
    if includeIgnoreRulesFile {
        try Data("version: 1\nignore: []\n".utf8).write(to: ignoreRulesURL, options: .withoutOverwriting)
    }

    return (repoURL, ignoreRulesURL)
}
