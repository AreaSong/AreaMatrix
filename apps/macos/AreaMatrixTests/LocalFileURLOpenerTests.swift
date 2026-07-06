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

        XCTAssertEqual(resourceReader.requestedURLs.map(\.path), [url.path])
        XCTAssertEqual(platformOpener.openedURLs.map(\.path), [url.path])
        XCTAssertEqual(platformOpener.revealedURLs, [])
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
        XCTAssertEqual(platformOpener.openedURLs, [])
        XCTAssertEqual(platformOpener.revealedURLs, [])
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
        XCTAssertEqual(platformOpener.openedURLs, [])
        XCTAssertEqual(platformOpener.revealedURLs, [])
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
        XCTAssertEqual(platformOpener.openedURLs.map(\.path), [url.path])
        XCTAssertEqual(platformOpener.revealedURLs, [])
    }

    @MainActor
    func testLocalFileURLOpenerRevealsExistingURL() throws {
        let url = URL(fileURLWithPath: "/tmp/reveal.txt")
        let resourceReader = RecordingLocalFileURLResourceReader(snapshot: .init(exists: true, isDirectory: false))
        let platformOpener = RecordingLocalFileURLPlatformOpener()
        let opener = NSWorkspaceLocalFileURLOpener(resourceReader: resourceReader, platformOpener: platformOpener)

        try opener.revealExisting(url)

        XCTAssertEqual(resourceReader.requestedURLs.map(\.path), [url.path])
        XCTAssertEqual(platformOpener.openedURLs, [])
        XCTAssertEqual(platformOpener.revealedURLs.map { $0.map(\.path) }, [[url.path]])
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
        XCTAssertEqual(fileOpener.openExistingRequests.map(\.url.path), ["/tmp/repo/docs/a.pdf"])
        XCTAssertEqual(fileOpener.openExistingRequests.map(\.requiresDirectory), [false])

        let revealer = RecordingLocalFileURLOpener()
        try NSWorkspaceRepositoryFileRevealer(localURLOpener: revealer)
            .revealFile(repoPath: repoPath, relativePath: "docs/a.pdf")
        XCTAssertEqual(revealer.revealExistingURLs.map(\.path), ["/tmp/repo/docs/a.pdf"])
    }

    @MainActor
    func testFeatureOpenersUseSharedLocalFileURLOpenerAndPreserveErrors() throws {
        let repoPath = "/tmp/repo"
        let logsPath = "/tmp/repo/.areamatrix/logs"

        let aboutLogsOpener = RecordingLocalFileURLOpener()
        let openedAboutLogsPath = try NSWorkspaceAboutLogsOpener(localURLOpener: aboutLogsOpener)
            .openLogs(repoPath: repoPath)
        XCTAssertEqual(openedAboutLogsPath, logsPath)
        XCTAssertEqual(aboutLogsOpener.openExistingRequests.map(\.url.path), [logsPath])
        XCTAssertEqual(aboutLogsOpener.openExistingRequests.map(\.requiresDirectory), [true])

        XCTAssertThrowsError(try NSWorkspaceAboutLogsOpener(
            localURLOpener: RecordingLocalFileURLOpener(result: .failure(LocalFileURLOpenError.openRejected(logsPath)))
        ).openLogs(repoPath: repoPath)) { error in
            XCTAssertEqual(error as? AboutSettingsPlatformError, .openRejected(logsPath))
        }

        XCTAssertThrowsError(try AdvancedSettingsLogFolderOpener(
            localURLOpener: RecordingLocalFileURLOpener(result: .failure(LocalFileURLOpenError.missing(logsPath)))
        ).openLogsFolder(repoPath: repoPath)) { error in
            XCTAssertEqual(error as? AdvancedSettingsLogFolderError, .missing(logsPath))
        }

        let diagnosticsRevealer = RecordingLocalFileURLOpener()
        try NSWorkspaceAboutDiagnosticsRevealer(localURLOpener: diagnosticsRevealer)
            .revealDiagnostics(at: "/tmp/diagnostics")
        XCTAssertEqual(diagnosticsRevealer.revealExistingURLs.map(\.path), ["/tmp/diagnostics"])

        XCTAssertThrowsError(try NSWorkspaceLocalModelFolderOpener(
            localURLOpener: RecordingLocalFileURLOpener(result: .failure(LocalFileURLOpenError.missing("/tmp/models")))
        ).openLocalModelFolder(localModelFolderLocation(folderPath: "/tmp/models"))) { error in
            XCTAssertEqual(error as? LocalModelStatusActionError, .openRejected)
        }
    }

    @MainActor
    func testWelcomeHelpOpenerUsesSharedLocalFileURLOpenerAndPreservesErrors() throws {
        let helpURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/product/prd.md")

        let welcomeHelpOpener = RecordingLocalFileURLOpener()
        try LocalWelcomeHelpOpener(localURLOpener: welcomeHelpOpener).openWelcomeHelp()
        XCTAssertEqual(welcomeHelpOpener.openExistingRequests.map(\.url.path), [helpURL.path])
        XCTAssertEqual(welcomeHelpOpener.openExistingRequests.map(\.requiresDirectory), [false])

        XCTAssertThrowsError(try LocalWelcomeHelpOpener(
            localURLOpener: RecordingLocalFileURLOpener(
                result: .failure(LocalFileURLOpenError.missing(helpURL.path))
            )
        ).openWelcomeHelp()) { error in
            XCTAssertEqual(error as? WelcomeHelpError, .helpDocumentUnavailable)
        }

        XCTAssertNoThrow(try LocalWelcomeHelpOpener(
            localURLOpener: RecordingLocalFileURLOpener(
                result: .failure(LocalFileURLOpenError.openRejected(helpURL.path))
            )
        ).openWelcomeHelp())
    }

    @MainActor
    func testIgnoreRulesOpenerUsesSharedLocalFileURLOpenerForExistingFile() throws {
        let fixture = try makeIgnoreRulesFixture(includeIgnoreRulesFile: true)
        defer { removeTestTemporaryItems(fixture.repoURL) }

        let localURLOpener = RecordingLocalFileURLOpener()
        try NSWorkspaceRepositoryIgnoreRulesManager(localURLOpener: localURLOpener)
            .openIgnoreRules(repoPath: fixture.repoURL.path)

        XCTAssertEqual(localURLOpener.openURLs.map(\.path), [fixture.ignoreRulesURL.path])
        XCTAssertTrue(localURLOpener.openExistingRequests.isEmpty)
        XCTAssertEqual(localURLOpener.revealExistingURLs, [])
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
        XCTAssertEqual(localURLOpener.openURLs.map(\.path), [fixture.ignoreRulesURL.path])
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
        XCTAssertEqual(localURLOpener.openURLs, [])
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
        XCTAssertEqual(localURLOpener.openURLs, [])
    }
}

@MainActor
private final class RecordingLocalFileURLResourceReader: LocalFileURLResourceReading {
    private let snapshot: LocalFileURLResourceSnapshot
    private(set) var requestedURLs: [URL] = []

    init(snapshot: LocalFileURLResourceSnapshot) {
        self.snapshot = snapshot
    }

    func resourceSnapshot(for url: URL) -> LocalFileURLResourceSnapshot {
        requestedURLs.append(url)
        return snapshot
    }
}

@MainActor
private final class RecordingLocalFileURLPlatformOpener: LocalFileURLPlatformOpening {
    private let openResult: Bool
    private(set) var openedURLs: [URL] = []
    private(set) var revealedURLs: [[URL]] = []

    init(openResult: Bool = true) {
        self.openResult = openResult
    }

    func open(_ url: URL) -> Bool {
        openedURLs.append(url)
        return openResult
    }

    func reveal(_ urls: [URL]) {
        revealedURLs.append(urls)
    }
}

@MainActor
private final class RecordingLocalFileURLOpener: LocalFileURLOpening {
    private let result: Result<Void, Error>
    private(set) var openURLs: [URL] = []
    private(set) var openExistingRequests: [(url: URL, requiresDirectory: Bool)] = []
    private(set) var revealExistingURLs: [URL] = []

    init(result: Result<Void, Error> = .success(())) {
        self.result = result
    }

    func open(_ url: URL) throws {
        openURLs.append(url)
        try result.get()
    }

    func openExisting(_ url: URL, requiresDirectory: Bool) throws {
        openExistingRequests.append((url, requiresDirectory))
        try result.get()
    }

    func revealExisting(_ url: URL) throws {
        revealExistingURLs.append(url)
        try result.get()
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
