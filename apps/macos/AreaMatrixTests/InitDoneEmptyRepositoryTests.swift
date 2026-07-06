@testable import AreaMatrix
import Foundation
import XCTest

final class InitDoneEmptyRepositoryTests: XCTestCase {
    @MainActor
    func testOpenRepositoryFromInitDoneUsesInitEmptyRepoCoreCoreOpenBoundary() async {
        let opening = RepositoryOpeningResult.initDoneFixture(repoPath: "/tmp/empty-repo", fileCount: 0)
        let opener = RecordingRepositoryOpener(result: .success(opening))
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            emptyRepositoryOpener: opener,
            startupRecoverer: StaticStartupRecoverer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.route = .initializationDone(RepositoryInitializationResult(
            repoPath: "/tmp/empty-repo",
            mode: .createEmpty,
            scanSession: nil,
            recoveryReport: nil
        ))
        await model.openInitializedRepository()

        let requestedRepoPaths = await opener.requestedEmptyRepoPaths()
        XCTAssertEqual(requestedRepoPaths, ["/tmp/empty-repo"])
        XCTAssertNil(model.initializationOpenErrorMapping)
        XCTAssertEqual(model.route, .mainEmpty(opening))
    }

    @MainActor
    func testOpenRepositoryFailureReturnsToDonePageWithInlineRetryError() async {
        let error = CoreError.Config(reason: "tree json unavailable")
        let mapping = CoreErrorMappingSnapshot.initDoneConfigFixture(rawContext: "tree json unavailable")
        let opener = RecordingRepositoryOpener(result: .failure(error))
        let errorMapper = StaticCoreErrorMapper(mapping: mapping)
        let result = RepositoryInitializationResult(
            repoPath: "/tmp/empty-repo",
            mode: .createEmpty,
            scanSession: nil,
            recoveryReport: nil
        )
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            emptyRepositoryOpener: opener,
            startupRecoverer: StaticStartupRecoverer(),
            errorMapper: errorMapper,
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.route = .initializationDone(result)
        await model.openInitializedRepository()

        XCTAssertEqual(model.route, .initializationDone(result))
        XCTAssertEqual(model.initializationOpenErrorMapping, mapping)
        let mappedErrors = await errorMapper.recordedErrors()
        XCTAssertEqual(mappedErrors, [error])
    }

    @MainActor
    func testOpenRepositoryShowsMainLoadingUntilCoreOpenCompletes() async {
        let opening = RepositoryOpeningResult.initDoneFixture(repoPath: "/tmp/empty-repo", fileCount: 0)
        let opener = PausingEmptyRepositoryOpener(opening: opening)
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            emptyRepositoryOpener: opener,
            startupRecoverer: StaticStartupRecoverer(),
            helpOpener: NoopWelcomeHelpOpener()
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

        XCTAssertEqual(model.route, .mainLoading(MainLoadingState(
            repoPath: "/tmp/empty-repo",
            startupRecovery: .completed(nil)
        )))
        await opener.finishOpen()
        await openTask.value
        XCTAssertEqual(model.route, .mainEmpty(opening))
    }

    func testDefaultCoreBridgeOpensRealEmptyRepositoryThroughLoadConfigAndTree() async throws {
        let repoURL = try makeInitDoneTemporaryRepositoryURL()
        defer { removeTestTemporaryItems(repoURL) }

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
    func testOpenRepositoryFromAdoptDoneUsesAdoptExistingRepoCoreCoreOpenBoundary() async {
        let opening = RepositoryOpeningResult.initDoneFixture(repoPath: "/tmp/adopted-repo", fileCount: 1)
        let opener = RecordingRepositoryOpener(result: .success(opening))
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            emptyRepositoryOpener: opener,
            startupRecoverer: StaticStartupRecoverer(),
            helpOpener: NoopWelcomeHelpOpener()
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
        let opener = RecordingRepositoryOpener(result: .failure(error))
        let errorMapper = StaticCoreErrorMapper(mapping: mapping)
        let result = RepositoryInitializationResult(
            repoPath: "/tmp/adopted-repo",
            mode: .adoptExisting,
            scanSession: ScanSessionSnapshot.adoptCompletedFixture(),
            recoveryReport: nil
        )
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            emptyRepositoryOpener: opener,
            startupRecoverer: StaticStartupRecoverer(),
            errorMapper: errorMapper,
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.route = .initializationDone(result)
        await model.openInitializedRepository()

        XCTAssertEqual(model.route, .initializationDone(result))
        XCTAssertEqual(model.initializationOpenErrorMapping, mapping)
        let mappedErrors = await errorMapper.recordedErrors()
        XCTAssertEqual(mappedErrors, [error])
    }

    @MainActor
    func testOpenInitDoneRepositoryInFinderReportsNonBlockingFailure() async {
        let finderOpener = RecordingRepositoryFinderOpener(
            result: .failure(RepositoryFinderOpenError.openRejected("/tmp/adopted-repo"))
        )
        let accessibilityAnnouncer = RecordingAccessibilityAnnouncer()
        let result = RepositoryInitializationResult(
            repoPath: "/tmp/adopted-repo",
            mode: .adoptExisting,
            scanSession: ScanSessionSnapshot.adoptCompletedFixture(),
            recoveryReport: nil
        )
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            finderOpener: finderOpener,
            accessibilityAnnouncer: accessibilityAnnouncer,
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.route = .initializationDone(result)
        await model.openInitializedRepositoryInFinder()
        guard let message = model.toastMessage else {
            return XCTFail("expected Finder failure toast")
        }

        XCTAssertEqual(finderOpener.repoPaths, ["/tmp/adopted-repo"])
        XCTAssertEqual(model.route, .initializationDone(result))
        XCTAssertTrue(message.contains("无法在 Finder 中打开资料库"))
        XCTAssertEqual(accessibilityAnnouncer.announcements, [message])
    }

    func testDefaultCoreBridgeOpensRealAdoptedRepositoryThroughLoadConfigAndTree() async throws {
        let repoURL = try makeInitDoneTemporaryRepositoryURL()
        defer { removeTestTemporaryItems(repoURL) }

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

    func testDefaultCoreBridgeReopensConfiguredEmptyRepositoryThroughTreeAndCurrentCategoryList() async throws {
        let repoURL = try makeInitDoneTemporaryRepositoryURL()
        defer { removeTestTemporaryItems(repoURL) }

        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let opening = try await bridge.openConfiguredRepository(repoPath: repoURL.path)

        XCTAssertTrue(opening.isEmpty)
        XCTAssertEqual(opening.tree.sidebarNodes.map(\.slug), ["inbox", "docs", "code", "design", "finance", "media"])
        XCTAssertEqual(opening.currentCategoryFiles, [])
    }

    func testOpeningResultIsNotEmptyWhenTreeCountAndCurrentCategoryListDisagree() {
        let staleTree = RepositoryTreeNodeSnapshot.testRoot(displayName: "资料库")
        let opening = RepositoryOpeningResult(
            config: .initDoneFixture(repoPath: "/tmp/repo"),
            tree: staleTree,
            currentCategoryFiles: [.initDoneFileFixture(category: "inbox")]
        )

        XCTAssertFalse(opening.isEmpty)
    }

    func testCurrentCategoryListFailureStaysInlineInsteadOfFailingRepositoryOpen() {
        let tree = RepositoryTreeNodeSnapshot.testRoot(displayName: "资料库")
        let mapping = CoreErrorMappingSnapshot.initDoneDbFixture(rawContext: "list db locked")

        let result = loadOpeningCurrentCategoryFiles(
            repoPath: "/tmp/repo",
            tree: tree,
            shouldLoad: true,
            listFiles: { _, _ in throw CoreError.Db(message: "list db locked") },
            mapError: { _ in mapping }
        )

        XCTAssertEqual(result.files, [])
        XCTAssertEqual(result.errorMapping, mapping)
    }
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

    func openEmptyRepository(repoPath _: String) async throws -> RepositoryOpeningResult {
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
