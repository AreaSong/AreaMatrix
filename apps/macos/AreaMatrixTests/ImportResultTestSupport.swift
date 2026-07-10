@testable import AreaMatrix
import XCTest

@MainActor
struct ImportResultMainListFixture {
    let opening: RepositoryOpeningResult
    let model: OnboardingModel
}

@MainActor
func makeImportResultMainListFixture(
    repoPath: String = importResultRepoPath(),
    settingsReader: any AppSettingsReading = StaticSettingsReader(repoPath: nil),
    importProgressImporter: (any CoreFileImporting)? = nil,
    importResultChangeLister: (any CoreChangeLogListing)? = nil,
    errorMapper: (any CoreErrorMapping)? = nil,
    fileRevealer: (any RepositoryFileRevealing)? = nil,
    importResultExporter: (any ImportResultDetailsExporting)? = nil,
    accessibilityAnnouncer: (any AccessibilityAnnouncing)? = nil,
    helpOpener: any WelcomeHelpOpening = NoopWelcomeHelpOpener()
) -> ImportResultMainListFixture {
    let fixture = makeShellMainListFixture(
        repoPath: repoPath,
        model: makeShellOnboardingModel(
            settingsReader: settingsReader,
            importProgressImporter: importProgressImporter ?? ImportSingleFileRecordingImporter(),
            importResultChangeLister: importResultChangeLister ?? RecordingChangeLogLister(entries: []),
            errorMapper: errorMapper ?? RecordingCoreErrorMapper.importSingleFile(),
            fileRevealer: fileRevealer ?? RecordingRepositoryFileRevealer(),
            importResultExporter: importResultExporter ?? ImportResultExporter(),
            accessibilityAnnouncer: accessibilityAnnouncer ?? RecordingAccessibilityAnnouncer(),
            helpOpener: helpOpener
        )
    )
    return ImportResultMainListFixture(opening: fixture.opening, model: fixture.model)
}

@MainActor
func requireImportProgressRoute(
    _ model: OnboardingModel,
    message: String = "Expected import-progress route",
    file: StaticString = #filePath,
    line: UInt = #line
) -> ImportProgressRouteState? {
    guard case let .importProgress(state) = model.route else {
        XCTFail("\(message), got \(model.route)", file: file, line: line)
        return nil
    }
    return state
}

@MainActor
func requireImportResultRoute(
    _ model: OnboardingModel,
    message: String = "Expected import-result route",
    file: StaticString = #filePath,
    line: UInt = #line
) -> ImportResultRouteState? {
    guard case let .importResult(state) = model.route else {
        XCTFail("\(message), got \(model.route)", file: file, line: line)
        return nil
    }
    return state
}

@MainActor
func showImportResultRoute(
    _ model: OnboardingModel,
    progress: ImportBatchProgressSnapshot,
    message: String = "Expected import-result route",
    file: StaticString = #filePath,
    line: UInt = #line
) -> ImportResultRouteState? {
    model.showImportEntryResults(progress)
    return requireImportResultRoute(model, message: message, file: file, line: line)
}

func requireImportResultItem(
    _ result: ImportResultRouteState,
    matching predicate: (ImportResultRouteState.Item) -> Bool,
    message: String,
    file: StaticString = #filePath,
    line: UInt = #line
) -> ImportResultRouteState.Item? {
    guard let item = result.items.first(where: predicate) else {
        XCTFail(message, file: file, line: line)
        return nil
    }
    return item
}

func assertImportResultSummary(
    _ result: ImportResultRouteState,
    summaryText: String,
    statuses expectedStatuses: [ImportResultRouteState.ItemStatus]? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(result.resultSummaryText, summaryText, file: file, line: line)
    if let expectedStatuses {
        XCTAssertEqual(result.items.map(\.status), expectedStatuses, file: file, line: line)
    }
}

func assertImportResultRetryAvailability(
    _ result: ImportResultRouteState,
    canRetryFailedItems: Bool,
    isRetryingFailedItems: Bool,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(result.canRetryFailedItems, canRetryFailedItems, file: file, line: line)
    XCTAssertEqual(result.isRetryingFailedItems, isRetryingFailedItems, file: file, line: line)
}

@MainActor
func waitForImportResultRoute(
    _ model: OnboardingModel,
    file: StaticString = #filePath,
    line: UInt = #line
) async -> ImportResultRouteState? {
    await waitForMainActorTestValue(
        failureMessage: { "Timed out waiting for import result route, got \(model.route)" },
        file: file,
        line: line,
        value: {
            if case let .importResult(state) = model.route { return state }
            return nil
        }
    )
}
