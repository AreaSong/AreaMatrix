import AreaMatrixCoreBridgeContract
@testable import AreaMatrix
import XCTest

@MainActor
struct ImportProgressMainListFixture {
    let opening: RepositoryOpeningResult
    let model: OnboardingModel
}

@MainActor
func makeImportProgressMainListFixture(
    repoPath: String = importProgressRepoPath(),
    settingsReader: any AppSettingsReading = StaticSettingsReader(repoPath: nil),
    importProgressImporter: any CoreFileImporting = ImportSingleFileRecordingImporter(),
    startupRecoverer: any CoreStartupRecovering = StaticStartupRecoverer(),
    diagnosticsCollector: any CoreDiagnosticsCollecting = ShellRecordingDiagnosticsCollector(
        result: .success(DiagnosticsSnapshotSnapshot.testFixture())
    ),
    finderOpener: (any RepositoryFinderOpening)? = nil,
    importProgressControlState: ImportProgressControlState = ImportProgressControlState(),
    accessibilityAnnouncer: (any AccessibilityAnnouncing)? = nil,
    helpOpener: any WelcomeHelpOpening = NoopWelcomeHelpOpener()
) -> ImportProgressMainListFixture {
    let fixture = makeShellMainListFixture(
        repoPath: repoPath,
        model: makeShellOnboardingModel(
            settingsReader: settingsReader,
            importProgressImporter: importProgressImporter,
            startupRecoverer: startupRecoverer,
            diagnosticsCollector: diagnosticsCollector,
            finderOpener: finderOpener ?? RecordingRepositoryFinderOpener(),
            importProgressControlState: importProgressControlState,
            accessibilityAnnouncer: accessibilityAnnouncer ?? RecordingAccessibilityAnnouncer(),
            helpOpener: helpOpener
        )
    )
    return ImportProgressMainListFixture(opening: fixture.opening, model: fixture.model)
}

extension OnboardingModel {
    var currentImportProgressState: ImportProgressRouteState? {
        guard case let .importProgress(state) = route else { return nil }
        return state
    }
}

func assertImportProgressRecoveryCheckPending(
    _ state: ImportProgressRouteState,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertFalse(state.canRetryCurrentItem, file: file, line: line)
    XCTAssertEqual(state.retryStatusText, "Checking recovery state...", file: file, line: line)
}

func assertImportProgressRetryReady(
    _ state: ImportProgressRouteState,
    retryContext: ImportProgressRetryContext,
    statusText: String? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertTrue(state.canRetryCurrentItem, file: file, line: line)
    assertImportProgressRetryContext(state.retryContext, equals: retryContext, file: file, line: line)
    if let statusText {
        XCTAssertEqual(state.retryStatusText, statusText, file: file, line: line)
    }
}

func assertImportProgressRetryContext(
    _ actual: ImportProgressRetryContext?,
    equals expected: ImportProgressRetryContext,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard let actual else {
        return XCTFail("Expected import retry context", file: file, line: line)
    }
    XCTAssertEqual(actual.repoPath, expected.repoPath, file: file, line: line)
    XCTAssertEqual(actual.sourcePath, expected.sourcePath, file: file, line: line)
    XCTAssertEqual(actual.storageMode, expected.storageMode, file: file, line: line)
    XCTAssertEqual(actual.overrideCategory, expected.overrideCategory, file: file, line: line)
    XCTAssertEqual(actual.overrideFilename, expected.overrideFilename, file: file, line: line)
    XCTAssertEqual(actual.duplicateStrategy, expected.duplicateStrategy, file: file, line: line)
    if let expectedTraceID = expected.traceID {
        XCTAssertEqual(actual.traceID, expectedTraceID, file: file, line: line)
    }
    if let expectedOperationID = expected.operationID {
        XCTAssertEqual(actual.operationID, expectedOperationID, file: file, line: line)
    }
}

@MainActor
func assertImportProgressRecoveryCheckAllowsRetry(
    _ model: OnboardingModel,
    recoverer: RecordingCoreStartupRecoverer,
    retryContext: ImportProgressRetryContext,
    failedRouteMessage: String,
    checkedRouteMessage: String,
    expectedRecovererRepoPaths: [String] = [importProgressRepoPath()],
    checkedStatusText: String? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    guard let failedBeforeCheck = requireImportProgressRoute(
        model,
        message: failedRouteMessage,
        file: file,
        line: line
    ) else { return }
    assertImportProgressRecoveryCheckPending(failedBeforeCheck, file: file, line: line)

    await model.checkImportProgressRecoveryIfNeeded()

    guard let checkedState = requireImportProgressRoute(
        model,
        message: checkedRouteMessage,
        file: file,
        line: line
    ) else { return }
    await recoverer.assertRequestedRepoPaths(expectedRecovererRepoPaths, file: file, line: line)
    assertImportProgressRetryReady(
        checkedState,
        retryContext: retryContext,
        statusText: checkedStatusText,
        file: file,
        line: line
    )
}

func assertSingleImportProgressItem(
    _ state: ImportProgressRouteState,
    titleText: String = "Importing 1 file",
    sourcePath: String,
    targetPath: String,
    phase: ImportBatchProgressSnapshot.Phase,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(state.titleText, titleText, file: file, line: line)
    XCTAssertEqual(state.items, [
        ImportBatchProgressSnapshot.Item(
            sourcePath: sourcePath,
            targetPath: targetPath,
            phase: phase,
            errorMessage: nil
        )
    ], file: file, line: line)
}

actor ImportProgressFatalCopyErrorMapper: CoreErrorMapping {
    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        switch error {
        case .Io: .importProgressFatalCopyError
        default: .importSingleFileError(kind: .internal)
        }
    }
}
