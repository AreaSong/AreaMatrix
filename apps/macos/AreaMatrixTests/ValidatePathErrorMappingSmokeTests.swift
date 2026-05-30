@testable import AreaMatrix
import XCTest

final class ValidatePathErrorMappingTests: XCTestCase {
    @MainActor
    func testValidatePathMapsCoreFailureThroughC121ErrorMapper() async {
        let mapping = CoreErrorMappingSnapshot.errorSmokePermissionDeniedFixture(rawContext: "/tmp/repo")
        let errorMapper = ErrorSmokeRecordingErrorMapper(mapping: mapping)
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            configLoader: ShellRecordingConfigLoader(result: .success(.shellFixture(repoPath: "/tmp/repo"))),
            pathValidator: ShellRecordingPathValidator(result: .failure(CoreError.PermissionDenied(path: "/tmp/repo"))),
            errorMapper: errorMapper,
            helpOpener: ShellNoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()

        XCTAssertEqual(errorMapper.mappedErrors, [CoreError.PermissionDenied(path: "/tmp/repo")])
        XCTAssertEqual(model.repositoryPathError, "无访问权限")
        XCTAssertEqual(model.repositoryPathErrorMapping, mapping)
        XCTAssertFalse(model.canContinueFromValidatePath)
    }

    func testCoreBridgeMapsCoreErrorThroughGeneratedBindings() async {
        let mapping = await CoreBridge().mapCoreError(CoreError.PermissionDenied(path: "/restricted/repo"))

        XCTAssertEqual(mapping.kind, .permissionDenied)
        XCTAssertEqual(mapping.userMessage, "无访问权限")
        XCTAssertEqual(mapping.severity, .high)
        XCTAssertEqual(mapping.recoverability, .userActionRequired)
        XCTAssertEqual(mapping.rawContext, "/restricted/repo")
        XCTAssertFalse(mapping.suggestedAction.isEmpty)
    }

    @MainActor
    func testConfigValidationFailureRoutesToMainRepoError() async {
        let mapping = CoreErrorMappingSnapshot.errorSmokeConfigFixture(rawContext: "schema mismatch")
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            configLoader: ShellRecordingConfigLoader(result: .success(.shellFixture(repoPath: "/tmp/repo"))),
            pathValidator: ShellRecordingPathValidator(result: .failure(CoreError.Config(reason: "schema mismatch"))),
            errorMapper: ErrorSmokeRecordingErrorMapper(mapping: mapping),
            helpOpener: ShellNoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()

        XCTAssertEqual(model.route, .mainRepoError("/tmp/repo", mapping))
        XCTAssertFalse(model.canContinueFromValidatePath)
    }
}

final class ValidatePathIntegrationSmokeTests: XCTestCase {
    @MainActor
    func testInsufficientCapacityBlocksValidatePathContinue() async {
        let validation = RepoPathValidationSnapshot.shellFixture(
            repoPath: "/tmp/repo",
            availableCapacityBytes: 128 * 1024 * 1024
        )
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            configLoader: ShellRecordingConfigLoader(result: .success(.shellFixture(repoPath: "/tmp/repo"))),
            pathValidator: ShellRecordingPathValidator(result: .success(validation)),
            helpOpener: ShellNoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()

        XCTAssertEqual(model.repositoryPathError, "可用空间不足，请释放空间或选择其他路径")
        XCTAssertFalse(model.canContinueFromValidatePath)
    }
}

final class QueryErrorDiagnosticSnapshotTests: XCTestCase {
    func testS205DiagnosticSnapshotPreservesCoreTokenRangeAndSuggestion() {
        let diagnostic = SearchQueryDiagnostic(
            kind: .unknownField,
            severity: .error,
            message: "Unknown field `kindd`",
            token: "kindd",
            start: 0,
            end: 5,
            suggestion: "kind"
        )
        let snapshot = SearchQueryDiagnosticSnapshot(coreDiagnostic: diagnostic)

        XCTAssertEqual(snapshot.kindDisplayName, "Unknown field")
        XCTAssertEqual(snapshot.severityDisplayName, "Error")
        XCTAssertEqual(snapshot.token, "kindd")
        XCTAssertEqual(snapshot.start, 0)
        XCTAssertEqual(snapshot.end, 5)
        XCTAssertEqual(snapshot.suggestion, "kind")
        XCTAssertEqual(snapshot.problemAccessibilityHint, "Token kindd. Position 0-5. Suggestion kind")
    }
}

final class S306AISummaryEditorModelTests: XCTestCase {
    @MainActor
    func testS306GenerateCreatesDraftWithoutSavingUntilExplicitSave() async {
        let bridge = S306AISummaryBridge()
        let model = AISummaryEditorModel(repoPath: "/tmp/repo", fileID: 606, summaryStore: bridge)

        await model.generate(regenerate: false)

        XCTAssertEqual(model.status, .draft)
        XCTAssertEqual(model.draftText, "Quarterly invoice with payment status and vendor context.")
        XCTAssertEqual(model.provenance?.route, .local)
        XCTAssertTrue(model.canSave)
        let generateEvents = await bridge.events()
        XCTAssertEqual(generateEvents, [.generate(fileID: 606, regenerate: false)])

        await model.save()

        let saveEvents = await bridge.events()
        XCTAssertEqual(model.status, .saved)
        XCTAssertEqual(model.draftText, "Quarterly invoice with payment status and vendor context.")
        XCTAssertEqual(saveEvents, [
            .generate(fileID: 606, regenerate: false),
            .save(fileID: 606, text: "Quarterly invoice with payment status and vendor context.", edited: false)
        ])
    }

    @MainActor
    func testS306FailurePreservesDraftAndMapsCoreError() async {
        let bridge = S306AISummaryBridge(saveResult: .failure(CoreError.Db(message: "summary metadata locked")))
        let mapper = S306SummaryErrorMapper()
        let model = AISummaryEditorModel(repoPath: "/tmp/repo", fileID: 607, summaryStore: bridge, errorMapper: mapper)

        await model.generate(regenerate: false)
        model.updateDraft("Edited summary")
        await model.save()

        guard case let .failed(error) = model.operation else {
            return XCTFail("Expected save failure to stay visible.")
        }
        let mappedErrors = await mapper.errors()
        XCTAssertEqual(model.draftText, "Edited summary")
        XCTAssertEqual(error.message, "Summary could not be saved.")
        XCTAssertEqual(error.detail, "Summary metadata is unavailable.")
        XCTAssertEqual(mappedErrors, [CoreError.Db(message: "summary metadata locked")])
    }

    @MainActor
    func testS306ClearOnlyCallsConfirmedSummaryClear() async {
        let bridge = S306AISummaryBridge()
        let model = AISummaryEditorModel(repoPath: "/tmp/repo", fileID: 608, summaryStore: bridge)

        await model.generate(regenerate: false)
        await model.clear()

        let clearEvents = await bridge.events()
        XCTAssertEqual(model.status, .empty)
        XCTAssertEqual(model.draftText, "")
        XCTAssertNil(model.provenance)
        XCTAssertEqual(clearEvents, [
            .generate(fileID: 608, regenerate: false),
            .clear(fileID: 608, confirmed: true)
        ])
    }
}

private final class ErrorSmokeRecordingErrorMapper: CoreErrorMapping {
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

private extension CoreErrorMappingSnapshot {
    static func errorSmokePermissionDeniedFixture(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .permissionDenied,
            userMessage: "无访问权限",
            severity: .high,
            suggestedAction: "请在系统设置中授予权限，或选择其他资料库位置",
            recoverability: .userActionRequired,
            rawContext: rawContext
        )
    }

    static func errorSmokeConfigFixture(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .config,
            userMessage: "资料库 schema 不兼容",
            severity: .critical,
            suggestedAction: "请选择其他资料库，或导出诊断信息",
            recoverability: .fatal,
            rawContext: rawContext
        )
    }
}

private enum S306SummaryEvent: Equatable {
    case generate(fileID: Int64, regenerate: Bool)
    case save(fileID: Int64, text: String, edited: Bool)
    case clear(fileID: Int64, confirmed: Bool)
}

private actor S306AISummaryBridge: CoreAISummaryManaging {
    private let saveResult: Result<AiSummarySaveReport, Error>?
    private var recordedEvents: [S306SummaryEvent] = []

    init(saveResult: Result<AiSummarySaveReport, Error>? = nil) {
        self.saveResult = saveResult
    }

    func generateAISummary(repoPath _: String, request: AiSummaryGenerationRequest) async throws -> AiSummaryDraft {
        recordedEvents.append(.generate(fileID: request.fileId, regenerate: request.regenerateExisting))
        return AiSummaryDraft(
            fileId: request.fileId,
            draftId: "draft-s306",
            status: .draft,
            summaryText: "Quarterly invoice with payment status and vendor context.",
            route: .local,
            modelName: "Local classifier v1",
            generatedAt: 1_700_000_000,
            usedContext: [.fileName, .extractedTextExcerpt],
            skippedReason: nil,
            privacyRuleId: nil,
            callLogId: 306,
            requiresUserSave: true,
            characterCount: 58
        )
    }

    func saveAISummary(repoPath _: String, request: AiSummarySaveRequest) async throws -> AiSummarySaveReport {
        recordedEvents.append(.save(fileID: request.fileId, text: request.summaryText, edited: request.editedByUser))
        if let saveResult {
            return try saveResult.get()
        }
        return AiSummarySaveReport(
            fileId: request.fileId,
            savedSummary: request.summaryText,
            savedAt: 1_700_000_100,
            route: request.route,
            modelName: request.modelName,
            generatedAt: request.generatedAt,
            usedContext: request.usedContext,
            privacyRuleId: request.privacyRuleId,
            callLogId: request.callLogId,
            editedByUser: request.editedByUser,
            characterCount: Int64(request.summaryText.count)
        )
    }

    func clearAISummary(repoPath _: String, request: AiSummaryClearRequest) async throws -> AiSummaryClearReport {
        recordedEvents.append(.clear(fileID: request.fileId, confirmed: request.confirmed))
        return AiSummaryClearReport(fileId: request.fileId, cleared: true, clearedAt: 1_700_000_200)
    }

    func events() -> [S306SummaryEvent] {
        recordedEvents
    }
}

private actor S306SummaryErrorMapper: CoreErrorMapping {
    private var recordedErrors: [CoreError] = []

    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        recordedErrors.append(error)
        return CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "Summary metadata is unavailable.",
            severity: .medium,
            suggestedAction: "Retry save.",
            recoverability: .retryable,
            rawContext: "S3-06 C3-06"
        )
    }

    func errors() -> [CoreError] {
        recordedErrors
    }
}
