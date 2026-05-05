import XCTest
@testable import AreaMatrix

final class MainLoadingAdoptExistingTests: XCTestCase {
    @MainActor
    func testInitializedAdoptOpenShowsLatestScanSessionInMainLoading() async {
        let scanSession = ScanSessionSnapshot.mainLoadingAdoptFixture(status: .running)
        let opener = MainLoadingPausingRepositoryOpener(
            opening: .mainLoadingFixture(repoPath: "/tmp/adopted-repo", fileCount: 1)
        )
        let model = OnboardingModel(
            settingsReader: MainLoadingStaticSettingsReader(repoPath: nil),
            emptyRepositoryOpener: opener,
            scanSessionReader: MainLoadingStaticScanSessionReader(result: .success(scanSession)),
            helpOpener: MainLoadingNoopWelcomeHelpOpener()
        )

        model.route = .initializationDone(RepositoryInitializationResult(
            repoPath: "/tmp/adopted-repo",
            mode: .adoptExisting,
            scanSession: nil,
            recoveryReport: nil
        ))
        let openTask = Task {
            await model.openInitializedRepository()
        }

        await opener.waitUntilStarted()
        guard case .mainLoading(let state) = model.route else {
            await opener.finishOpen()
            await openTask.value
            return XCTFail("expected main loading, got \(model.route)")
        }

        XCTAssertEqual(state.repoPath, "/tmp/adopted-repo")
        XCTAssertEqual(state.scanSession, scanSession)
        XCTAssertEqual(state.adoptStatusText, "正在扫描资料库 15")
        XCTAssertEqual(state.adoptProgressText, "新增 12，更新 2，跳过 1")
        XCTAssertEqual(state.adoptCurrentPathText, "当前路径：docs/plan.md")

        await opener.finishOpen()
        await openTask.value
    }

    @MainActor
    func testMainLoadingMapsLatestScanSessionFailureWithoutBlockingRepositoryOpen() async {
        let mapping = CoreErrorMappingSnapshot.mainLoadingDbFixture(rawContext: "scan db locked")
        let opener = MainLoadingPausingRepositoryOpener(
            opening: .mainLoadingFixture(repoPath: "/tmp/adopted-repo", fileCount: 1)
        )
        let model = OnboardingModel(
            settingsReader: MainLoadingStaticSettingsReader(repoPath: nil),
            emptyRepositoryOpener: opener,
            scanSessionReader: MainLoadingStaticScanSessionReader(result: .failure(CoreError.Db(message: "scan db locked"))),
            errorMapper: MainLoadingRecordingErrorMapper(mapping: mapping),
            helpOpener: MainLoadingNoopWelcomeHelpOpener()
        )

        model.route = .initializationDone(RepositoryInitializationResult(
            repoPath: "/tmp/adopted-repo",
            mode: .adoptExisting,
            scanSession: nil,
            recoveryReport: nil
        ))
        let openTask = Task {
            await model.openInitializedRepository()
        }

        await opener.waitUntilStarted()
        guard let state = await waitForMainLoadingState(model, matching: { $0.scanSessionErrorMapping != nil }) else {
            await opener.finishOpen()
            await openTask.value
            return
        }

        XCTAssertEqual(state.scanSessionErrorMapping, mapping)
        XCTAssertEqual(state.adoptStatusText, "接管扫描状态不可用：扫描状态暂不可用")

        await opener.finishOpen()
        await openTask.value
    }

    @MainActor
    func testCancelMainOpeningDoesNotSaveConfiguredRepoOrApplyLateOpenResult() async {
        let writer = MainLoadingRecordingSettingsWriter()
        let opening = RepositoryOpeningResult.mainLoadingFixture(repoPath: "/tmp/repo", fileCount: 1)
        let opener = MainLoadingPausingRepositoryOpener(opening: opening)
        let model = OnboardingModel(
            settingsReader: MainLoadingStaticSettingsReader(repoPath: nil),
            settingsWriter: writer,
            emptyRepositoryOpener: opener,
            scanSessionReader: MainLoadingStaticScanSessionReader(result: .success(nil)),
            helpOpener: MainLoadingNoopWelcomeHelpOpener()
        )

        let validation = RepoPathValidationSnapshot.mainLoadingInitializedFixture(repoPath: "/tmp/repo")
        let openTask = Task {
            await model.openExistingRepository(validation)
        }
        await opener.waitUntilStarted()

        model.cancelMainOpening()
        await opener.finishOpen()
        await openTask.value

        XCTAssertEqual(writer.savedRepoPaths, [])
        XCTAssertEqual(model.route, .validatePath)
        XCTAssertEqual(model.repositoryPathText, "/tmp/repo")
        XCTAssertEqual(
            model.toastMessage,
            "Opening was cancelled. Repository configuration and user files were not changed."
        )
    }
}

private enum MainLoadingScanSessionResult {
    case success(ScanSessionSnapshot?)
    case failure(Error)
}

private actor MainLoadingStaticScanSessionReader: CoreScanSessionReading {
    private let result: MainLoadingScanSessionResult

    init(result: MainLoadingScanSessionResult) {
        self.result = result
    }

    func latestScanSession(repoPath: String) async throws -> ScanSessionSnapshot? {
        switch result {
        case .success(let session):
            return session
        case .failure(let error):
            throw error
        }
    }
}

private actor MainLoadingPausingRepositoryOpener: CoreEmptyRepositoryOpening {
    private let opening: RepositoryOpeningResult
    private var didStart = false
    private var didFinish = false
    private var startContinuations: [CheckedContinuation<Void, Never>] = []
    private var finishContinuation: CheckedContinuation<Void, Never>?

    init(opening: RepositoryOpeningResult) {
        self.opening = opening
    }

    func openConfiguredRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        await pauseUntilFinished()
        return opening
    }

    func openEmptyRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        try await openConfiguredRepository(repoPath: repoPath)
    }

    func openAdoptedRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        try await openConfiguredRepository(repoPath: repoPath)
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

    private func pauseUntilFinished() async {
        didStart = true
        resumeStartContinuations()
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

private final class MainLoadingRecordingSettingsWriter: AppSettingsWriting {
    private(set) var savedRepoPaths: [String] = []

    func saveConfiguredRepoPath(_ repoPath: String) {
        savedRepoPaths.append(repoPath)
    }
}

private final class MainLoadingRecordingErrorMapper: CoreErrorMapping {
    private let mapping: CoreErrorMappingSnapshot

    init(mapping: CoreErrorMappingSnapshot) {
        self.mapping = mapping
    }

    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        mapping
    }
}

private struct MainLoadingStaticSettingsReader: AppSettingsReading {
    let repoPath: String?

    func configuredRepoPath() -> String? { repoPath }
}

private struct MainLoadingNoopWelcomeHelpOpener: WelcomeHelpOpening {
    func openWelcomeHelp() throws {}
}

@MainActor
private func waitForMainLoadingState(
    _ model: OnboardingModel,
    matching predicate: (MainLoadingState) -> Bool,
    file: StaticString = #filePath,
    line: UInt = #line
) async -> MainLoadingState? {
    for _ in 0..<100 {
        if case .mainLoading(let state) = model.route, predicate(state) {
            return state
        }

        await Task.yield()
    }

    XCTFail("Timed out waiting for matching main loading state, got \(model.route)", file: file, line: line)
    return nil
}

private extension RepositoryOpeningResult {
    static func mainLoadingFixture(repoPath: String, fileCount: Int64) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .mainLoadingFixture(repoPath: repoPath),
            tree: RepositoryTreeNodeSnapshot(slug: "__root__", displayName: "资料库", fileCount: fileCount, children: []),
            currentCategoryFiles: []
        )
    }
}

private extension RepoConfigSnapshot {
    static func mainLoadingFixture(repoPath: String) -> RepoConfigSnapshot {
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

private extension RepoPathValidationSnapshot {
    static func mainLoadingInitializedFixture(repoPath: String) -> RepoPathValidationSnapshot {
        RepoPathValidationSnapshot(
            repoPath: repoPath,
            exists: true,
            isDirectory: true,
            isReadable: true,
            isWritable: true,
            isEmpty: false,
            isInitialized: true,
            isInsideAreaMatrix: false,
            isICloudPath: false,
            hasUnfinishedScanSession: false,
            availableCapacityBytes: 1_073_741_824,
            isExternalVolume: false,
            recommendedMode: nil,
            issues: [.alreadyInitialized]
        )
    }
}

private extension ScanSessionSnapshot {
    static func mainLoadingAdoptFixture(status: ScanSessionStatusSnapshot) -> ScanSessionSnapshot {
        ScanSessionSnapshot(
            id: 42,
            kind: .adopt,
            status: status,
            lastPath: "docs/plan.md",
            inserted: 12,
            updated: 2,
            skipped: 1,
            startedAt: 1_700_000_000,
            updatedAt: 1_700_000_010,
            finishedAt: nil,
            errors: []
        )
    }
}

private extension CoreErrorMappingSnapshot {
    static func mainLoadingDbFixture(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "扫描状态暂不可用",
            severity: .medium,
            suggestedAction: "资料库打开后可重试扫描状态读取。",
            recoverability: .retryable,
            rawContext: rawContext
        )
    }
}
