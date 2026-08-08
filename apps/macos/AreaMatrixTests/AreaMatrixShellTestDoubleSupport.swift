@testable import AreaMatrix
import AreaMatrixCoreBridgeContract
import XCTest

typealias ShellStaticSettingsReader = StaticSettingsReader

typealias ShellRecordingSettingsWriter = RecordingAppSettingsWriter

typealias ShellRecordingConfigLoader = RecordingConfigurationLoader

typealias ShellRecordingRepositoryOpener = RecordingRepositoryOpener

typealias ShellRecordingPathValidator = RecordingRepositoryPathValidator

typealias ShellRecordingInitializedPathValidator = RecordingRepositoryPathValidator

typealias ShellRecordingExternalChangesSyncer = RecordingExternalChangesSyncer

typealias ShellRecordingDiagnosticsCollector = RecordingDiagnosticsCollector

typealias ShellRecordingRepositoryInitializer = RecordingRepositoryInitializer

typealias ShellStaticScanSessionReader = StaticScanSessionReader

typealias ShellStaticImportBatchSessionStore = StaticImportBatchSessionStore

struct ShellFailingWelcomeHelpOpener: WelcomeHelpOpening {
    func openWelcomeHelp() throws {
        throw WelcomeHelpError.helpDocumentUnavailable
    }
}

@MainActor
final class ShellRecordingPathCopier: RepositoryPathCopying {
    struct Request: Equatable {
        var repoPath: String
        var relativePath: String
    }

    struct MultiPathRequest: Equatable {
        var repoPath: String
        var relativePaths: [String]
    }

    private var requests: [Request] = []
    private var multiPathRequests: [MultiPathRequest] = []

    func copyPath(repoPath: String, relativePath: String) throws {
        requests.append(Request(repoPath: repoPath, relativePath: relativePath))
    }

    func copyPaths(repoPath: String, relativePaths: [String]) throws {
        multiPathRequests.append(MultiPathRequest(repoPath: repoPath, relativePaths: relativePaths))
    }

    func assertCopiedPathRequests(
        _ expectedRequests: [Request],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requests, expectedRequests, file: file, line: line)
    }

    func assertMultiPathRequests(
        _ expectedRequests: [MultiPathRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(multiPathRequests, expectedRequests, file: file, line: line)
    }
}

typealias ShellExistingRepoMetadataReader = StaticExistingRepositoryMetadataReader

extension RecordingCoreErrorMapper {
    static func shell() -> RecordingCoreErrorMapper {
        RecordingCoreErrorMapper { error in
            let kind = CoreErrorKindTestMapper.kind(for: error)
            return CoreErrorMappingSnapshot.localized(CoreErrorLocalizedSnapshotInput(
                kind: kind,
                userMessage: shellUserMessage(for: kind),
                severity: shellSeverity(for: kind),
                suggestedAction: shellSuggestedAction(for: kind),
                recoverability: shellRecoverability(for: kind),
                rawContext: shellRawContext(for: error)
            ))
        }
    }

    private static func shellUserMessage(for kind: CoreErrorKindSnapshot) -> String {
        switch kind {
        case .permissionDenied:
            "无访问权限"
        case .db:
            "数据库错误"
        case .repoNotInitialized:
            "资料库尚未初始化"
        case .invalidPath:
            "路径无效"
        case .internal:
            "应用内部错误"
        default:
            "操作失败"
        }
    }

    private static func shellSeverity(for kind: CoreErrorKindSnapshot) -> CoreErrorSeveritySnapshot {
        kind == .db ? .high : .medium
    }

    private static func shellSuggestedAction(for kind: CoreErrorKindSnapshot) -> String {
        kind == .db ? "检查资料库数据库后重试" : "Retry"
    }

    private static func shellRecoverability(for kind: CoreErrorKindSnapshot) -> CoreErrorRecoverabilitySnapshot {
        kind == .db ? .userActionRequired : .retryable
    }

    private static func shellRawContext(for error: CoreError) -> String {
        switch error {
        case let .Io(message),
             let .Db(message),
             let .DbLocked(message),
             let .DbCorrupted(message),
             let .Internal(message):
            message
        case let .Config(reason),
             let .Validation(reason),
             let .Classify(reason):
            reason
        case let .Conflict(path),
             let .DuplicateFile(path),
             let .FileNotFound(path),
             let .ExpiredAction(path),
             let .RepoNotInitialized(path),
             let .InvalidPath(path),
             let .ICloudPlaceholder(path),
             let .StagingRecoveryRequired(path),
             let .PermissionDenied(path):
            path
        case let .RevisionConflict(resource, expectedRevision, currentRevision):
            "\(resource): expected \(expectedRevision), current \(currentRevision)"
        }
    }
}

@MainActor
func makeShellOnboardingModel(
    repoPath: String? = nil,
    settingsReader: (any AppSettingsReading)? = nil,
    settingsWriter: any AppSettingsWriting = ShellRecordingSettingsWriter(),
    configLoader: any CoreConfigurationLoading = ShellRecordingConfigLoader(
        result: .success(.shellFixture(repoPath: "/tmp/repo"))
    ),
    pathValidator: any CoreRepositoryPathValidating = ShellRecordingPathValidator(
        result: .success(.shellFixture(repoPath: "/tmp/repo"))
    ),
    initializedPathValidator: any CoreInitializedRepositoryPathValidating = ShellRecordingInitializedPathValidator(
        result: .success(.shellFixture(repoPath: "/tmp/repo"))
    ),
    repositoryInitializer: any CoreRepositoryInitializing = ShellRecordingRepositoryInitializer(),
    emptyRepositoryOpener: any CoreEmptyRepositoryOpening = ShellRecordingRepositoryOpener(
        result: .success(.shellFixture(repoPath: "/tmp/repo", fileCount: 0))
    ),
    importProgressImporter: (any CoreFileImporting)? = nil,
    importResultChangeLister: (any CoreChangeLogListing)? = nil,
    mainLoadingTreeLister: (any CoreRepositoryTreeListing)? = nil,
    startupRecoverer: any CoreStartupRecovering = StaticStartupRecoverer(),
    externalChangesSyncer: any CoreExternalChangesSyncing = ShellRecordingExternalChangesSyncer(
        result: .success(.testFixture())
    ),
    existingRepositoryMetadataReader: any ExistingRepositoryMetadataReading =
        ShellExistingRepoMetadataReader(schemaVersion: 1),
    scanSessionReader: any CoreScanSessionReading = ShellStaticScanSessionReader(session: nil),
    diagnosticsCollector: (any CoreDiagnosticsCollecting)? = nil,
    errorMapper: (any CoreErrorMapping)? = nil,
    finderOpener: (any RepositoryFinderOpening)? = nil,
    fileRevealer: (any RepositoryFileRevealing)? = nil,
    fileOpener: (any RepositoryFileOpening)? = nil,
    pathCopier: (any RepositoryPathCopying)? = nil,
    importResultExporter: (any ImportResultDetailsExporting)? = nil,
    importBatchSessionStore: any ImportBatchSessionPersisting = ShellStaticImportBatchSessionStore(session: nil),
    systemCapabilityChecker: any OnboardingSystemCapabilityChecking = StaticOnboardingSystemCapabilityChecker(),
    importProgressControlState: ImportProgressControlState? = nil,
    accessibilityAnnouncer: (any AccessibilityAnnouncing)? = nil,
    directoryPicker: (any RepositoryDirectoryPicking)? = nil,
    importPicker: any RepositoryImportPicking = ShellStaticImportPicker(urls: nil),
    helpOpener: any WelcomeHelpOpening = NoopWelcomeHelpOpener()
) -> OnboardingModel {
    OnboardingModel(
        settingsReader: settingsReader ?? ShellStaticSettingsReader(repoPath: repoPath),
        settingsWriter: settingsWriter,
        configLoader: configLoader,
        pathValidator: pathValidator,
        initializedPathValidator: initializedPathValidator,
        repositoryInitializer: repositoryInitializer,
        emptyRepositoryOpener: emptyRepositoryOpener,
        importProgressImporter: importProgressImporter ?? ImportSingleFileRecordingImporter(),
        importResultChangeLister: importResultChangeLister ?? RecordingChangeLogLister(entries: []),
        mainLoadingTreeLister: mainLoadingTreeLister,
        startupRecoverer: startupRecoverer,
        externalChangesSyncer: externalChangesSyncer,
        existingRepositoryMetadataReader: existingRepositoryMetadataReader,
        scanSessionReader: scanSessionReader,
        diagnosticsCollector: diagnosticsCollector ?? ShellRecordingDiagnosticsCollector(
            result: .success(DiagnosticsSnapshotSnapshot.testFixture())
        ),
        errorMapper: errorMapper ?? RecordingCoreErrorMapper.shell(),
        finderOpener: finderOpener ?? RecordingRepositoryFinderOpener(),
        fileRevealer: fileRevealer ?? RecordingRepositoryFileRevealer(),
        fileOpener: fileOpener ?? RecordingRepositoryFileOpener(),
        pathCopier: pathCopier ?? ShellRecordingPathCopier(),
        importResultExporter: importResultExporter ?? ImportResultExporter(),
        importBatchSessionStore: importBatchSessionStore,
        systemCapabilityChecker: systemCapabilityChecker,
        importProgressControlState: importProgressControlState ?? ImportProgressControlState(),
        accessibilityAnnouncer: accessibilityAnnouncer ?? RecordingAccessibilityAnnouncer(),
        helpOpener: helpOpener,
        directoryPicker: directoryPicker ?? ShellRecordingDirectoryPicker(selectedURL: nil),
        importPicker: importPicker
    )
}

@MainActor
struct ShellMainListFixture {
    let opening: RepositoryOpeningResult
    let model: OnboardingModel
}

@MainActor
func makeShellMainListFixture(repoPath: String, model: OnboardingModel) -> ShellMainListFixture {
    let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: repoPath)
    return makeShellMainListFixture(opening: opening, model: model)
}

@MainActor
func makeShellMainListFixture(opening: RepositoryOpeningResult, model: OnboardingModel) -> ShellMainListFixture {
    model.route = .mainList(opening)
    return ShellMainListFixture(opening: opening, model: model)
}

@MainActor
struct ShellSettingsGeneralFixture {
    let opening: RepositoryOpeningResult
    let model: OnboardingModel
}

@MainActor
func makeShellSettingsGeneralFixture(
    opening: RepositoryOpeningResult,
    selectedTab: String = "general",
    model: OnboardingModel
) -> ShellSettingsGeneralFixture {
    model.route = .settingsGeneral(opening)
    model.settingsGeneralSelectedTab = selectedTab
    return ShellSettingsGeneralFixture(opening: opening, model: model)
}

@MainActor
func requireMainEmptyRoute(
    _ model: OnboardingModel,
    message: String = "Expected main-empty route",
    file: StaticString = #filePath,
    line: UInt = #line
) -> RepositoryOpeningResult? {
    guard case let .mainEmpty(opening) = model.route else {
        XCTFail("\(message), got \(model.route)", file: file, line: line)
        return nil
    }
    return opening
}

@MainActor
func requireMainListRoute(
    _ model: OnboardingModel,
    message: String = "Expected main-list route",
    file: StaticString = #filePath,
    line: UInt = #line
) -> RepositoryOpeningResult? {
    guard case let .mainList(opening) = model.route else {
        XCTFail("\(message), got \(model.route)", file: file, line: line)
        return nil
    }
    return opening
}

@MainActor
func waitForMainListRoute(
    _ model: OnboardingModel,
    file: StaticString = #filePath,
    line: UInt = #line
) async -> RepositoryOpeningResult? {
    await waitForMainActorTestValue(
        failureMessage: { "Timed out waiting for main list route, got \(model.route)" },
        file: file,
        line: line,
        value: {
            if case let .mainList(opening) = model.route { return opening }
            return nil
        }
    )
}

@MainActor
func requireMainRepoErrorRoute(
    _ model: OnboardingModel,
    message: String = "Expected main repo error route",
    file: StaticString = #filePath,
    line: UInt = #line
) -> (repoPath: String, mapping: CoreErrorMappingSnapshot?)? {
    guard case let .mainRepoError(repoPath, mapping) = model.route else {
        XCTFail("\(message), got \(model.route)", file: file, line: line)
        return nil
    }
    return (repoPath: repoPath, mapping: mapping)
}

@MainActor
func requireDatabaseRepairRoute(
    _ model: OnboardingModel,
    message: String = "Expected database repair route",
    file: StaticString = #filePath,
    line: UInt = #line
) -> DatabaseRepairRouteState? {
    guard case let .dbRepairConfirm(repairRoute) = model.route else {
        XCTFail("\(message), got \(model.route)", file: file, line: line)
        return nil
    }
    return repairRoute
}

@MainActor
final class ShellRecordingDirectoryPicker: RepositoryDirectoryPicking {
    private let selectedURL: URL?
    private var chooseCount = 0

    init(selectedURL: URL?) {
        self.selectedURL = selectedURL
    }

    func chooseDirectory() -> URL? {
        chooseCount += 1
        return selectedURL
    }

    func assertChooseCount(
        _ expectedCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(chooseCount, expectedCount, file: file, line: line)
    }
}

struct ShellStaticImportPicker: RepositoryImportPicking {
    let urls: [URL]?

    func chooseImportURLs() -> [URL]? {
        urls
    }
}
