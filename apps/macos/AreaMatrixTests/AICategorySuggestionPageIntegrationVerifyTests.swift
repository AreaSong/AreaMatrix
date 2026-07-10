@testable import AreaMatrix
import XCTest

final class AICategorySuggestionVerifyTests: XCTestCase {
    @MainActor
    func testAcceptRequiresPreviewThenAppliesThroughClassifierCorrectionBridge() async {
        let original = aiCategorySuggestionFile(id: 590)
        let corrected = aiCategorySuggestionFile(
            id: original.id,
            path: "finance/invoices/invoice.pdf",
            category: "finance/invoices"
        )
        let preview = aiCategorySuggestionPreview(fileID: original.id)
        let mover = AICategorySuggestionMover(
            previewResult: .success(preview),
            correctionResult: .success(aiCategorySuggestionCorrection(updatedFile: corrected))
        )
        let model = aiCategorySuggestionMainModel(file: original, mover: mover)
        let suggestion = AIClassificationSuggestionState.aiCategorySuggestionSuggested(fileID: original.id)

        model.beginAIClassificationSuggestion(fileID: original.id)
        await model.loadMoveToCategoryPreview(fileID: original.id, targetCategory: "finance/invoices")
        let didApply = await model.submitAIClassificationSuggestion(AIClassificationSuggestionApplyRequest(
            fileID: original.id,
            targetCategory: "finance/invoices",
            moveFile: true,
            rememberRule: false,
            suggestion: suggestion,
            preview: preview
        ))

        XCTAssertTrue(didApply)
        await mover.assertRequests([
            .preview(fileID: original.id, targetCategory: "finance/invoices"),
            .correction(fileID: original.id, targetCategory: "finance/invoices", moveFile: true, remember: false)
        ])
        XCTAssertEqual(model.selectedFileDetail, corrected)
        XCTAssertEqual(model.pendingActionDestination?.pageID, "ai-category-suggestion")
        XCTAssertEqual(
            model.pendingActionDestination?.aiClassificationReturnContext?.appliedCategory,
            "finance/invoices"
        )
    }

    @MainActor
    func testAcceptFailureKeepsAICategorySuggestionPanelOpenWithRetryEvidence() async {
        let original = aiCategorySuggestionFile(id: 591)
        let preview = aiCategorySuggestionPreview(fileID: original.id)
        let mover = AICategorySuggestionMover(
            previewResult: .success(preview),
            correctionResult: .failure(CoreError.Classify(reason: "target unavailable"))
        )
        let model = aiCategorySuggestionMainModel(file: original, mover: mover)
        let suggestion = AIClassificationSuggestionState.aiCategorySuggestionSuggested(fileID: original.id)

        model.beginAIClassificationSuggestion(fileID: original.id)
        let didApply = await model.submitAIClassificationSuggestion(AIClassificationSuggestionApplyRequest(
            fileID: original.id,
            targetCategory: "finance/invoices",
            moveFile: true,
            rememberRule: false,
            suggestion: suggestion,
            preview: preview
        ))

        XCTAssertFalse(didApply)
        XCTAssertEqual(model.pendingActionDestination, .aiClassificationSuggestion(fileID: original.id))
        XCTAssertEqual(model.files.first, original)
        XCTAssertEqual(
            model.changeCategoryState.failureOperation(for: original.id, targetCategory: "finance/invoices"),
            .correction
        )
    }

    @MainActor
    func testRejectRecordsVisibleFeedbackWithoutCoreMutation() async {
        let suggestion = AIClassificationSuggestionState.aiCategorySuggestionSuggested(fileID: 592)
        let model = aiCategorySuggestionSuggestionModel(
            request: AIClassificationSuggestionRequestState(fileID: 592, contextPolicy: .limitedTextSummary),
            bridge: AICategorySuggestionSuggestionBridge(result: .success(suggestion))
        )
        await model.askForSuggestion()
        var panel = AIClassificationSuggestionPanel(
            model: model,
            fileName: "invoice.pdf",
            currentPath: "inbox/invoice.pdf"
        )

        let feedback = panel.rejectSuggestion(suggestion)

        XCTAssertEqual(feedback.message, "Suggestion rejected. Feedback recorded for this review.")
        XCTAssertTrue(feedback.matches(suggestion))
    }

    @MainActor
    func testRememberRuleFromAICategorySuggestionCarriesAIProvenanceAndCancelReturnsToPanel() async {
        let original = aiCategorySuggestionFile(id: 593)
        let corrected = aiCategorySuggestionFile(
            id: original.id,
            path: "finance/invoices/invoice.pdf",
            category: "finance/invoices"
        )
        let mover =
            AICategorySuggestionMover(
                correctionResult: .success(aiCategorySuggestionCorrection(updatedFile: corrected))
            )
        let model = aiCategorySuggestionMainModel(file: original, mover: mover)
        let suggestion = AIClassificationSuggestionState.aiCategorySuggestionSuggested(fileID: original.id)

        model.beginAIClassificationSuggestion(fileID: original.id)
        let didApply = await model.submitAIClassificationSuggestion(AIClassificationSuggestionApplyRequest(
            fileID: original.id,
            targetCategory: "finance/invoices",
            moveFile: true,
            rememberRule: true,
            suggestion: suggestion,
            preview: aiCategorySuggestionPreview(fileID: original.id)
        ))

        XCTAssertTrue(didApply)
        XCTAssertEqual(model.pendingActionDestination?.pageID, "classifier-rule-save")
        guard case let .saveRule(handoff) = model.pendingActionDestination?.classifierRuleRoute else {
            return XCTFail("Expected ai-category-suggestion to route into classifier-rule-save rule save.")
        }
        XCTAssertEqual(handoff.sourcePageID, "ai-category-suggestion")
        XCTAssertEqual(handoff.aiProvenance?.suggestedCategory, "finance/invoices")
        XCTAssertEqual(handoff.aiProvenance?.finalCategory, "finance/invoices")
        XCTAssertEqual(handoff.aiProvenance?.callLogID, 304)
        XCTAssertTrue(handoff.summaryRows.map(\.label).contains("AI reason"))

        model.cancelClassifierRuleRoute()

        XCTAssertEqual(model.pendingActionDestination?.pageID, "ai-category-suggestion")
        XCTAssertEqual(model.pendingActionDestination?.aiClassificationReturnContext?.ruleStatus, .cancelled)
    }

    @MainActor
    func testViewAICallLoadsClassificationLogDetailThroughCoreBridgeContract() async {
        let record = aiCategorySuggestionCallLogRecord(id: 304)
        let lister = AICategorySuggestionCallLogLister(page: AiCallLogPage(
            totalCount: 1,
            records: [record],
            limit: 100,
            offset: 0,
            hasMore: false,
            retentionDays: 30,
            redactionPolicy: "redacted"
        ))
        let model = AIClassificationCallLogDetailModel(
            repoPath: "/tmp/repo",
            callLogID: 304,
            lister: lister,
            errorMapper: StaticCoreErrorMapper(mapping: .aiCategorySuggestionPageFailure)
        )

        await model.load()

        XCTAssertEqual(model.record, record)
        await lister.assertFirstRequest(feature: .classification)
    }
}

private enum AICategorySuggestionCategoryMoveRequest: Equatable {
    case preview(fileID: Int64, targetCategory: String)
    case correction(fileID: Int64, targetCategory: String, moveFile: Bool, remember: Bool)
}

private actor AICategorySuggestionMover: CoreFileCategoryMoving {
    private let previewResult: Result<MoveToCategoryPreviewSnapshot, Error>
    private let correctionResult: Result<ClassifierCorrectionResultSnapshot, Error>
    private var recordedRequests: [AICategorySuggestionCategoryMoveRequest] = []

    init(
        previewResult: Result<MoveToCategoryPreviewSnapshot, Error> = .failure(CoreError.Internal(message: "preview")),
        correctionResult: Result<ClassifierCorrectionResultSnapshot, Error>
    ) {
        self.previewResult = previewResult
        self.correctionResult = correctionResult
    }

    func previewMoveToCategory(
        repoPath _: String,
        fileID: Int64,
        newCategory: String
    ) async throws -> MoveToCategoryPreviewSnapshot {
        recordedRequests.append(.preview(fileID: fileID, targetCategory: newCategory))
        return try previewResult.get()
    }

    func moveToCategory(repoPath _: String, fileID _: Int64, newCategory _: String) async throws -> FileEntrySnapshot {
        throw CoreError.Internal(message: "ai-category-suggestion must use classifier correction apply")
    }

    func correctFileCategory(
        repoPath _: String,
        fileID: Int64,
        targetCategory: String,
        moveFile: Bool,
        remember: Bool
    ) async throws -> ClassifierCorrectionResultSnapshot {
        recordedRequests.append(.correction(
            fileID: fileID,
            targetCategory: targetCategory,
            moveFile: moveFile,
            remember: remember
        ))
        return try correctionResult.get()
    }

    func assertRequests(
        _ expectedRequests: [AICategorySuggestionCategoryMoveRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(recordedRequests, expectedRequests, file: file, line: line)
    }
}

private typealias AICategorySuggestionCallLogLister = RecordingAICallLogLister

@MainActor
private func aiCategorySuggestionMainModel(
    file: FileEntrySnapshot,
    mover: any CoreFileCategoryMoving
) -> MainFileListModel {
    MainFileListModel(
        opening: .aiCategorySuggestionFixture(repoPath: "/tmp/repo", files: [file]),
        fileLister: NoopFileLister(),
        fileDetailer: AICategorySuggestionDetailer(file: file),
        fileCategoryMover: mover,
        changeLogLister: AICategorySuggestionChangeLogLister(entries: []),
        errorMapper: StaticCoreErrorMapper(mapping: .aiCategorySuggestionPageFailure)
    )
}

private func aiCategorySuggestionFile(
    id: Int64,
    path: String = "inbox/invoice.pdf",
    category: String = "inbox"
) -> FileEntrySnapshot {
    FileEntrySnapshot.testFixture(
        id: id,
        path: path,
        currentName: "invoice.pdf",
        category: category
    ) {
        $0.hashSha256 = "aiCategorySuggestion-\(id)"
    }
}

private func aiCategorySuggestionPreview(fileID: Int64) -> MoveToCategoryPreviewSnapshot {
    MoveToCategoryPreviewSnapshot.testFixture(
        fileID: fileID,
        fromCategory: "inbox",
        toCategory: "finance/invoices",
        targetName: "invoice.pdf"
    )
}

private func aiCategorySuggestionCorrection(updatedFile: FileEntrySnapshot) -> ClassifierCorrectionResultSnapshot {
    ClassifierCorrectionResultSnapshot.testFixture(
        updatedFile: updatedFile,
        ruleDraft: .testFixture(
            sourceFileID: updatedFile.id,
            targetCategory: updatedFile.category,
            keywordCandidates: ["invoice"],
            extensionCandidates: ["pdf"],
            priority: 0
        ),
        moveFileRequested: true,
        rememberRequested: true,
        ruleConfirmationRequired: true
    )
}

private func aiCategorySuggestionCallLogRecord(id: Int64) -> AiCallLogRecord {
    AiCallLogRecord(
        id: id,
        occurredAt: 1_700_000_000,
        feature: .classification,
        fileId: 590,
        fileDisplayName: "invoice.pdf",
        batchId: nil,
        scope: "single",
        route: .remote,
        providerName: "OpenAI",
        modelName: "gpt-4.1-mini",
        status: .success,
        durationMs: 120,
        sentFields: [.fileName, .extension],
        privacyRulesChecked: true,
        privacyRuleId: nil,
        privacyRuleName: nil,
        matchedFieldType: nil,
        resultSummary: "finance/invoices",
        errorCode: nil
    )
}

private typealias AICategorySuggestionDetailer = DetailMetaImmediateDetailer

private typealias AICategorySuggestionChangeLogLister = RecordingChangeLogLister

private extension CoreErrorMappingSnapshot {
    static var aiCategorySuggestionPageFailure: CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: .classify,
            userMessage: "ai-category-suggestion apply failed",
            severity: .medium,
            suggestedAction: "Retry apply or classify manually.",
            recoverability: .retryable,
            rawContext: "ai-category-suggestion ai-classification-suggestion"
        )
    }
}

private extension RepositoryOpeningResult {
    static func aiCategorySuggestionFixture(repoPath: String, files: [FileEntrySnapshot]) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .testFixture(repoPath: repoPath) {
                $0.aiEnabled = true
            },
            tree: .testRoot(fileCount: 1),
            currentCategoryFiles: files,
            isReadOnly: false,
            writeLockedFileIDs: []
        )
    }
}
