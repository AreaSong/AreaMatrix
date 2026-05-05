import Foundation
import XCTest
@testable import AreaMatrix

final class InitDoneEmptyRepositoryTests: XCTestCase {
    @MainActor
    func testOpenRepositoryFromInitDoneUsesC102CoreOpenBoundary() async {
        let opening = RepositoryOpeningResult.initDoneFixture(repoPath: "/tmp/empty-repo", fileCount: 0)
        let opener = RecordingEmptyRepositoryOpener(result: .success(opening))
        let model = OnboardingModel(
            settingsReader: InitDoneStaticSettingsReader(repoPath: nil),
            emptyRepositoryOpener: opener,
            helpOpener: InitDoneNoopWelcomeHelpOpener()
        )

        model.route = .initializationDone(RepositoryInitializationResult(
            repoPath: "/tmp/empty-repo",
            mode: .createEmpty,
            scanSession: nil,
            recoveryReport: nil
        ))
        await model.openInitializedRepository()

        let requestedRepoPaths = await opener.requestedRepoPaths()
        XCTAssertEqual(requestedRepoPaths, ["/tmp/empty-repo"])
        XCTAssertNil(model.initializationOpenErrorMapping)
        XCTAssertEqual(model.route, .mainEmpty(opening))
    }

    @MainActor
    func testOpenRepositoryFailureReturnsToDonePageWithInlineRetryError() async {
        let error = CoreError.Config(reason: "tree json unavailable")
        let mapping = CoreErrorMappingSnapshot.initDoneConfigFixture(rawContext: "tree json unavailable")
        let opener = RecordingEmptyRepositoryOpener(result: .failure(error))
        let errorMapper = InitDoneRecordingErrorMapper(mapping: mapping)
        let result = RepositoryInitializationResult(
            repoPath: "/tmp/empty-repo",
            mode: .createEmpty,
            scanSession: nil,
            recoveryReport: nil
        )
        let model = OnboardingModel(
            settingsReader: InitDoneStaticSettingsReader(repoPath: nil),
            emptyRepositoryOpener: opener,
            errorMapper: errorMapper,
            helpOpener: InitDoneNoopWelcomeHelpOpener()
        )

        model.route = .initializationDone(result)
        await model.openInitializedRepository()

        XCTAssertEqual(model.route, .initializationDone(result))
        XCTAssertEqual(model.initializationOpenErrorMapping, mapping)
        XCTAssertEqual(errorMapper.mappedErrors, [error])
    }

    @MainActor
    func testOpenRepositoryShowsMainLoadingUntilCoreOpenCompletes() async {
        let opening = RepositoryOpeningResult.initDoneFixture(repoPath: "/tmp/empty-repo", fileCount: 0)
        let opener = PausingEmptyRepositoryOpener(opening: opening)
        let model = OnboardingModel(
            settingsReader: InitDoneStaticSettingsReader(repoPath: nil),
            emptyRepositoryOpener: opener,
            helpOpener: InitDoneNoopWelcomeHelpOpener()
        )

        model.route = .initializationDone(RepositoryInitializationResult(
            repoPath: "/tmp/empty-repo",
            mode: .createEmpty,
            scanSession: nil,
            recoveryReport: nil
        ))
        let openTask = Task {
            await model.openInitializedRepository()
        }

        await opener.waitUntilStarted()

        XCTAssertEqual(model.route, .mainLoading("/tmp/empty-repo"))
        await opener.finishOpen()
        await openTask.value
        XCTAssertEqual(model.route, .mainEmpty(opening))
    }

    func testDefaultCoreBridgeOpensRealEmptyRepositoryThroughLoadConfigAndTree() async throws {
        let repoURL = try makeTemporaryRepositoryURL()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let listedFiles = try await bridge.listFiles(repoPath: repoURL.path, filter: .currentCategory("inbox"))
        let opening = try await bridge.openEmptyRepository(repoPath: repoURL.path)

        XCTAssertEqual(opening.config.repoPath, repoURL.path)
        XCTAssertEqual(opening.config.locale, "zh-Hans")
        XCTAssertTrue(opening.isEmpty)
        XCTAssertEqual(opening.tree.totalFileCount, 0)
        XCTAssertEqual(listedFiles, [])
        XCTAssertEqual(opening.currentCategoryFiles, [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent(".areamatrix").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("README.md").path))
    }

    @MainActor
    func testOpenRepositoryFromAdoptDoneUsesC103CoreOpenBoundary() async {
        let opening = RepositoryOpeningResult.initDoneFixture(repoPath: "/tmp/adopted-repo", fileCount: 1)
        let opener = RecordingEmptyRepositoryOpener(result: .success(opening))
        let model = OnboardingModel(
            settingsReader: InitDoneStaticSettingsReader(repoPath: nil),
            emptyRepositoryOpener: opener,
            helpOpener: InitDoneNoopWelcomeHelpOpener()
        )

        model.route = .initializationDone(RepositoryInitializationResult(
            repoPath: "/tmp/adopted-repo",
            mode: .adoptExisting,
            scanSession: ScanSessionSnapshot.adoptCompletedFixture(),
            recoveryReport: nil
        ))
        await model.openInitializedRepository()

        let opened = await opener.requestedAdoptedRepoPaths()
        XCTAssertEqual(opened, ["/tmp/adopted-repo"])
        XCTAssertNil(model.initializationOpenErrorMapping)
        XCTAssertEqual(model.route, .mainList(opening))
    }

    @MainActor
    func testAdoptOpenFailureReturnsToDonePageWithInlineRetryError() async {
        let error = CoreError.Db(message: "tree unavailable")
        let mapping = CoreErrorMappingSnapshot.initDoneDbFixture(rawContext: "tree unavailable")
        let opener = RecordingEmptyRepositoryOpener(result: .failure(error))
        let errorMapper = InitDoneRecordingErrorMapper(mapping: mapping)
        let result = RepositoryInitializationResult(
            repoPath: "/tmp/adopted-repo",
            mode: .adoptExisting,
            scanSession: ScanSessionSnapshot.adoptCompletedFixture(),
            recoveryReport: nil
        )
        let model = OnboardingModel(
            settingsReader: InitDoneStaticSettingsReader(repoPath: nil),
            emptyRepositoryOpener: opener,
            errorMapper: errorMapper,
            helpOpener: InitDoneNoopWelcomeHelpOpener()
        )

        model.route = .initializationDone(result)
        await model.openInitializedRepository()

        XCTAssertEqual(model.route, .initializationDone(result))
        XCTAssertEqual(model.initializationOpenErrorMapping, mapping)
        XCTAssertEqual(errorMapper.mappedErrors, [error])
    }

    @MainActor
    func testOpenInitDoneRepositoryInFinderReportsNonBlockingFailure() async {
        let finderOpener = RecordingFinderOpener(result: .failure(.openRejected("/tmp/adopted-repo")))
        let accessibilityAnnouncer = RecordingAccessibilityAnnouncer()
        let result = RepositoryInitializationResult(
            repoPath: "/tmp/adopted-repo",
            mode: .adoptExisting,
            scanSession: ScanSessionSnapshot.adoptCompletedFixture(),
            recoveryReport: nil
        )
        let model = OnboardingModel(
            settingsReader: InitDoneStaticSettingsReader(repoPath: nil),
            finderOpener: finderOpener,
            accessibilityAnnouncer: accessibilityAnnouncer,
            helpOpener: InitDoneNoopWelcomeHelpOpener()
        )

        model.route = .initializationDone(result)
        await model.openInitializedRepositoryInFinder()
        guard let message = model.toastMessage else {
            return XCTFail("expected Finder failure toast")
        }

        XCTAssertEqual(finderOpener.openedRepoPaths, ["/tmp/adopted-repo"])
        XCTAssertEqual(model.route, .initializationDone(result))
        XCTAssertTrue(message.contains("无法在 Finder 中打开资料库"))
        XCTAssertEqual(accessibilityAnnouncer.announcements, [message])
    }

    func testDefaultCoreBridgeOpensRealAdoptedRepositoryThroughLoadConfigAndTree() async throws {
        let repoURL = try makeTemporaryRepositoryURL()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let readmeURL = repoURL.appendingPathComponent("README.md")
        try "# User project\n".write(to: readmeURL, atomically: true, encoding: .utf8)

        let bridge = CoreBridge()
        try await bridge.adoptExistingRepository(repoPath: repoURL.path)
        let opening = try await bridge.openAdoptedRepository(repoPath: repoURL.path)

        XCTAssertEqual(opening.config.repoPath, repoURL.path)
        XCTAssertEqual(opening.config.locale, "zh-Hans")
        XCTAssertFalse(opening.isEmpty)
        XCTAssertGreaterThan(opening.tree.totalFileCount, 0)
        XCTAssertEqual(try String(contentsOf: readmeURL, encoding: .utf8), "# User project\n")
        XCTAssertTrue(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent(".areamatrix").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("AREAMATRIX.md").path))
    }
}

private enum EmptyRepositoryOpenResult {
    case success(RepositoryOpeningResult)
    case failure(Error)
}

private actor RecordingEmptyRepositoryOpener: CoreEmptyRepositoryOpening {
    private let result: EmptyRepositoryOpenResult
    private var paths: [String] = []
    private var adoptedPaths: [String] = []

    init(result: EmptyRepositoryOpenResult) {
        self.result = result
    }

    func openEmptyRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        paths.append(repoPath)
        switch result {
        case .success(let opening):
            return opening
        case .failure(let error):
            throw error
        }
    }

    func openAdoptedRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        adoptedPaths.append(repoPath)
        switch result {
        case .success(let opening):
            return opening
        case .failure(let error):
            throw error
        }
    }

    func requestedRepoPaths() -> [String] { paths }
    func requestedAdoptedRepoPaths() -> [String] { adoptedPaths }
}

private actor PausingEmptyRepositoryOpener: CoreEmptyRepositoryOpening {
    private let opening: RepositoryOpeningResult
    private var didStart = false
    private var didFinish = false
    private var startContinuations: [CheckedContinuation<Void, Never>] = []
    private var finishContinuation: CheckedContinuation<Void, Never>?

    init(opening: RepositoryOpeningResult) {
        self.opening = opening
    }

    func openEmptyRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        didStart = true
        resumeStartContinuations()
        await waitForFinishSignal()
        return opening
    }

    func openAdoptedRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        try await openEmptyRepository(repoPath: repoPath)
    }

    func waitUntilStarted() async {
        guard !didStart else { return }

        await withCheckedContinuation { continuation in
            startContinuations.append(continuation)
        }
    }

    func finishOpen() {
        didFinish = true
        finishContinuation?.resume()
        finishContinuation = nil
    }

    private func waitForFinishSignal() async {
        guard !didFinish else { return }

        await withCheckedContinuation { continuation in
            finishContinuation = continuation
        }
    }

    private func resumeStartContinuations() {
        let continuations = startContinuations
        startContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }
}

private final class RecordingFinderOpener: RepositoryFinderOpening {
    private let result: Result<Void, RepositoryFinderOpenError>
    private(set) var openedRepoPaths: [String] = []

    init(result: Result<Void, RepositoryFinderOpenError>) {
        self.result = result
    }

    @MainActor
    func openRepositoryInFinder(repoPath: String) throws {
        openedRepoPaths.append(repoPath)
        try result.get()
    }
}

@MainActor
private final class RecordingAccessibilityAnnouncer: AccessibilityAnnouncing {
    private(set) var announcements: [String] = []

    func announce(_ message: String) {
        announcements.append(message)
    }
}

private struct InitDoneStaticSettingsReader: AppSettingsReading {
    let repoPath: String?

    func configuredRepoPath() -> String? { repoPath }
}

private struct InitDoneNoopWelcomeHelpOpener: WelcomeHelpOpening {
    func openWelcomeHelp() throws {}
}

private final class InitDoneRecordingErrorMapper: CoreErrorMapping {
    private let mapping: CoreErrorMappingSnapshot
    private(set) var mappedErrors: [CoreError] = []

    init(mapping: CoreErrorMappingSnapshot) {
        self.mapping = mapping
    }

    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        mappedErrors.append(error)
        return mapping
    }
}

private extension RepoConfigSnapshot {
    static func initDoneFixture(repoPath: String) -> RepoConfigSnapshot {
        RepoConfigSnapshot(
            repoPath: repoPath,
            defaultMode: "Copied",
            overviewOutput: "GeneratedOnly",
            aiEnabled: false,
            locale: "zh-Hans",
            iCloudWarn: true,
            enableExtensionRules: true,
            enableKeywordRules: true,
            fallbackToInbox: true,
            allowReplaceDuringImport: false
        )
    }
}

private extension RepositoryOpeningResult {
    static func initDoneFixture(repoPath: String, fileCount: Int64) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .initDoneFixture(repoPath: repoPath),
            tree: RepositoryTreeNodeSnapshot(
                slug: "__root__",
                displayName: "资料库",
                fileCount: fileCount,
                children: []
            ),
            currentCategoryFiles: []
        )
    }
}

private extension CoreErrorMappingSnapshot {
    static func initDoneConfigFixture(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .config,
            userMessage: "资料库配置不可用",
            severity: .high,
            suggestedAction: "请重试打开资料库，或重新选择资料库位置。",
            recoverability: .retryable,
            rawContext: rawContext
        )
    }

    static func initDoneDbFixture(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "资料库树不可用",
            severity: .high,
            suggestedAction: "请重试打开资料库，或重新选择资料库位置。",
            recoverability: .retryable,
            rawContext: rawContext
        )
    }
}

private extension ScanSessionSnapshot {
    static func adoptCompletedFixture() -> ScanSessionSnapshot {
        ScanSessionSnapshot(
            id: 42,
            kind: .adopt,
            status: .completed,
            lastPath: "README.md",
            inserted: 1,
            updated: 0,
            skipped: 0,
            startedAt: 1_700_000_000,
            updatedAt: 1_700_000_001,
            finishedAt: 1_700_000_001,
            errors: []
        )
    }
}

private func makeTemporaryRepositoryURL() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixInitDoneTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
