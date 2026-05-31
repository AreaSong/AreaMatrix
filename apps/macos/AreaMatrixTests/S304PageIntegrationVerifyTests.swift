@testable import AreaMatrix
import XCTest

final class S304PageIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testAcceptRequiresPreviewThenAppliesThroughClassifierCorrectionBridge() async {
        let original = s304File(id: 590)
        let corrected = s304File(id: original.id, path: "finance/invoices/invoice.pdf", category: "finance/invoices")
        let preview = s304Preview(fileID: original.id)
        let mover = S304RecordingCategoryMover(
            previewResult: .success(preview),
            correctionResult: .success(s304Correction(updatedFile: corrected))
        )
        let model = s304MainModel(file: original, mover: mover)
        let suggestion = AIClassificationSuggestionState.s304Suggested(fileID: original.id)

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
        let requests = await mover.requests()

        XCTAssertTrue(didApply)
        XCTAssertEqual(requests, [
            .preview(fileID: original.id, targetCategory: "finance/invoices"),
            .correction(fileID: original.id, targetCategory: "finance/invoices", moveFile: true, remember: false)
        ])
        XCTAssertEqual(model.selectedFileDetail, corrected)
        XCTAssertEqual(model.pendingActionDestination?.pageID, "S3-04")
        XCTAssertEqual(model.pendingActionDestination?.aiClassificationReturnContext?.appliedCategory, "finance/invoices")
    }

    @MainActor
    func testAcceptFailureKeepsS304PanelOpenWithRetryEvidence() async {
        let original = s304File(id: 591)
        let preview = s304Preview(fileID: original.id)
        let mover = S304RecordingCategoryMover(
            previewResult: .success(preview),
            correctionResult: .failure(CoreError.Classify(reason: "target unavailable"))
        )
        let model = s304MainModel(file: original, mover: mover)
        let suggestion = AIClassificationSuggestionState.s304Suggested(fileID: original.id)

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
        let suggestion = AIClassificationSuggestionState.s304Suggested(fileID: 592)
        let model = s304SuggestionModel(
            request: AIClassificationSuggestionRequestState(fileID: 592, contextPolicy: .limitedTextSummary),
            bridge: S304SuggestionBridge(result: .success(suggestion))
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
    func testRememberRuleFromS304CarriesAIProvenanceAndCancelReturnsToPanel() async {
        let original = s304File(id: 593)
        let corrected = s304File(id: original.id, path: "finance/invoices/invoice.pdf", category: "finance/invoices")
        let mover = S304RecordingCategoryMover(correctionResult: .success(s304Correction(updatedFile: corrected)))
        let model = s304MainModel(file: original, mover: mover)
        let suggestion = AIClassificationSuggestionState.s304Suggested(fileID: original.id)

        model.beginAIClassificationSuggestion(fileID: original.id)
        let didApply = await model.submitAIClassificationSuggestion(AIClassificationSuggestionApplyRequest(
            fileID: original.id,
            targetCategory: "finance/invoices",
            moveFile: true,
            rememberRule: true,
            suggestion: suggestion,
            preview: s304Preview(fileID: original.id)
        ))

        XCTAssertTrue(didApply)
        XCTAssertEqual(model.pendingActionDestination?.pageID, "S2-17")
        guard case let .saveRule(handoff) = model.pendingActionDestination?.classifierRuleRoute else {
            return XCTFail("Expected S3-04 to route into S2-17 rule save.")
        }
        XCTAssertEqual(handoff.sourcePageID, "S3-04")
        XCTAssertEqual(handoff.aiProvenance?.suggestedCategory, "finance/invoices")
        XCTAssertEqual(handoff.aiProvenance?.finalCategory, "finance/invoices")
        XCTAssertEqual(handoff.aiProvenance?.callLogID, 304)
        XCTAssertTrue(handoff.summaryRows.map(\.label).contains("AI reason"))

        model.cancelClassifierRuleRoute()

        XCTAssertEqual(model.pendingActionDestination?.pageID, "S3-04")
        XCTAssertEqual(model.pendingActionDestination?.aiClassificationReturnContext?.ruleStatus, .cancelled)
    }

    @MainActor
    func testViewAICallLoadsClassificationLogDetailThroughCoreBridgeContract() async throws {
        let record = s304CallLogRecord(id: 304)
        let lister = S304CallLogLister(page: AiCallLogPage(
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
            errorMapper: S304PageErrorMapper()
        )

        await model.load()
        let requests = await lister.requests()

        XCTAssertEqual(model.record, record)
        XCTAssertEqual(requests.first?.filter.feature, .classification)
        XCTAssertEqual(requests.first?.pagination.limit, 100)
    }

    @MainActor
    func testS307C307AITagSuggestionSkipsDisableAllSubmitActions() {
        let states = [
            AITagSuggestionState.loaded(
                fileID: 707,
                s307AITagReport(fileID: 707, status: .skipped, skippedReason: .privacyRule),
                []
            ),
            .loaded(fileID: 708, s307AITagReport(fileID: 708, status: .noSuggestion), []),
            .loaded(fileID: 709, s307AITagReport(
                fileID: 709,
                suggestions: [s307AITagSuggestion(id: "s3-07-low", slug: "maybe", confidence: 0.55)]
            ), [])
        ]

        for state in states {
            XCTAssertFalse(state.hasHighConfidenceApplyCandidates)
            XCTAssertFalse(state.canApplySelectedSuggestions)
            XCTAssertFalse(state.canEditSelectedSuggestions)
            XCTAssertEqual(AITagSuggestionAction.selectedApplyItems(in: state), [])
        }
    }

    @MainActor
    func testS307C307AcceptHighConfidenceExcludesPreviouslySelectedLowConfidence() {
        let report = s307AITagReport(fileID: 707, suggestions: [
            s307AITagSuggestion(id: "s3-07-finance", slug: "finance", confidence: 0.91, selectedByDefault: false),
            s307AITagSuggestion(id: "s3-07-low", slug: "maybe", confidence: 0.42, selectedByDefault: false)
        ])
        let lowSelected = AITagSuggestionState.loaded(fileID: 707, report, ["s3-07-low"])
        let highConfidenceOnly = AITagSuggestionAction.selectingHighConfidence(in: lowSelected)

        XCTAssertEqual(highConfidenceOnly.selectedIDs, ["s3-07-finance"])
        XCTAssertEqual(
            AITagSuggestionAction.selectedApplyItems(in: highConfidenceOnly).map(\.suggestionId),
            ["s3-07-finance"]
        )
    }

    @MainActor
    func testS307C307AITagSuggestionUsesCoreBridgeAndAppliesOnlyReviewedTags() async {
        let file = FileEntrySnapshot.detailMetaFixture(id: 707, currentName: "invoice.pdf")
        let bridge = S307AITagBridge(s307AITagReport(fileID: file.id, suggestions: [
            s307AITagSuggestion(id: "s3-07-finance", slug: "finance", confidence: 0.91),
            s307AITagSuggestion(id: "s3-07-low", slug: "maybe", confidence: 0.42, selectedByDefault: false)
        ]))
        let privacy = RemotePrivacyRulesBridge(snapshot: .s303PrivacyRules(featureScope: [.autoTags]))
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [file]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(file)),
            tagStore: DetailTagRecordingStore(listResults: [.success(.s207Fixture(fileID: file.id, values: ["client"]))]),
            aiTagSuggestionStore: bridge,
            aiPrivacyRules: privacy,
            changeLogLister: DetailLogRecordingChangeLister(entries: [.s223Applied()]),
            errorMapper: DetailMetaErrorMapper(mapping: .s207TagDb())
        )

        await model.selectFiles([file.id])
        await model.loadSelectedFileTags()
        await model.loadSelectedFileAITagSuggestions()
        let undoState = await model.applySelectedFileAITagSuggestions()
        let requests = await bridge.requests()
        let privacyRequests = await privacy.requests()

        XCTAssertEqual(requests.suggest.first?.fileId, file.id)
        XCTAssertEqual(requests.suggest.first?.candidateTags, ["client"])
        XCTAssertEqual(privacyRequests.evaluations.first?.feature, .autoTags)
        XCTAssertEqual(requests.apply.first?.fileId, file.id)
        XCTAssertEqual(requests.apply.first?.confirmed, true)
        XCTAssertEqual(requests.apply.first?.callLogId, 7_707)
        XCTAssertEqual(requests.apply.first?.suggestions.map(\.suggestionId), ["s3-07-finance"])
        XCTAssertEqual(model.aiTagSuggestionState.appliedReport?.appliedCount, 1)
        XCTAssertEqual(model.detailTagEditorState.tagSet?.fileTags.map(\.value), ["finance"])
        XCTAssertNil(undoState)
    }

    @MainActor
    func testS307C307SingleRowAddImmediatelyAppliesThroughCoreBridge() async {
        let file = FileEntrySnapshot.detailMetaFixture(id: 710, currentName: "invoice-single-add.pdf")
        let bridge = S307AITagBridge(s307AITagReport(fileID: file.id, suggestions: [
            s307AITagSuggestion(id: "s3-07-finance", slug: "finance", confidence: 0.91, selectedByDefault: false),
            s307AITagSuggestion(id: "s3-07-low", slug: "maybe", confidence: 0.42, selectedByDefault: false)
        ]))
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [file]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(file)),
            tagStore: DetailTagRecordingStore(listResults: [.success(.s207Fixture(fileID: file.id, values: []))]),
            aiTagSuggestionStore: bridge,
            aiPrivacyRules: RemotePrivacyRulesBridge(snapshot: .s303PrivacyRules(featureScope: [.autoTags])),
            changeLogLister: DetailLogRecordingChangeLister(entries: [.s223Applied()]),
            errorMapper: DetailMetaErrorMapper(mapping: .s207TagDb())
        )

        await model.selectFiles([file.id])
        await model.loadSelectedFileAITagSuggestions()
        let undoState = await model.applySelectedFileAITagSuggestion("s3-07-finance")
        let requests = await bridge.requests()

        XCTAssertEqual(model.aiTagSuggestionState.selectedIDs, [])
        XCTAssertEqual(requests.apply.count, 1)
        XCTAssertEqual(requests.apply.first?.fileId, file.id)
        XCTAssertEqual(requests.apply.first?.confirmed, true)
        XCTAssertEqual(requests.apply.first?.suggestions.map(\.suggestionId), ["s3-07-finance"])
        XCTAssertEqual(model.aiTagSuggestionState.appliedReport?.appliedCount, 1)
        XCTAssertEqual(model.detailTagEditorState.tagSet?.fileTags.map(\.value), ["finance"])
        XCTAssertNil(undoState)
    }

}

private enum S304CategoryMoveRequest: Equatable {
    case preview(fileID: Int64, targetCategory: String)
    case correction(fileID: Int64, targetCategory: String, moveFile: Bool, remember: Bool)
}

private actor S304RecordingCategoryMover: CoreFileCategoryMoving {
    private let previewResult: Result<MoveToCategoryPreviewSnapshot, Error>
    private let correctionResult: Result<ClassifierCorrectionResultSnapshot, Error>
    private var recordedRequests: [S304CategoryMoveRequest] = []

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
        throw CoreError.Internal(message: "S3-04 must use classifier correction apply")
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

    func requests() -> [S304CategoryMoveRequest] {
        recordedRequests
    }
}

private actor S304CallLogLister: CoreAICallLogListing {
    typealias Request = (filter: AiCallLogFilter, pagination: AiCallLogPagination)

    private let page: AiCallLogPage
    private var recordedRequests: [Request] = []

    init(page: AiCallLogPage) {
        self.page = page
    }

    func listAICalls(
        repoPath _: String,
        filter: AiCallLogFilter,
        pagination: AiCallLogPagination
    ) async throws -> AiCallLogPage {
        recordedRequests.append((filter, pagination))
        return page
    }

    func requests() -> [Request] {
        recordedRequests
    }
}

@MainActor
private func s304MainModel(
    file: FileEntrySnapshot,
    mover: any CoreFileCategoryMoving
) -> MainFileListModel {
    MainFileListModel(
        opening: .s304Fixture(repoPath: "/tmp/repo", files: [file]),
        fileLister: S304NoopLister(),
        fileDetailer: S304Detailer(file: file),
        fileCategoryMover: mover,
        changeLogLister: S304ChangeLogLister(),
        errorMapper: S304PageErrorMapper()
    )
}

private func s304File(
    id: Int64,
    path: String = "inbox/invoice.pdf",
    category: String = "inbox"
) -> FileEntrySnapshot {
    FileEntrySnapshot(
        id: id,
        path: path,
        originalName: "invoice.pdf",
        currentName: "invoice.pdf",
        category: category,
        sizeBytes: 128,
        hashSha256: "s304-\(id)",
        storageMode: "Copied",
        origin: "Imported",
        sourcePath: nil,
        importedAt: 1_700_000_000,
        updatedAt: 1_700_000_100
    )
}

private func s304Preview(fileID: Int64) -> MoveToCategoryPreviewSnapshot {
    MoveToCategoryPreviewSnapshot(
        fileID: fileID,
        fromCategory: "inbox",
        toCategory: "finance/invoices",
        currentPath: "inbox/invoice.pdf",
        targetPath: "finance/invoices/invoice.pdf",
        targetName: "invoice.pdf",
        storageMode: "Copied",
        indexOnly: false,
        nameConflictResolved: false,
        willMoveFile: true
    )
}

private func s304Correction(updatedFile: FileEntrySnapshot) -> ClassifierCorrectionResultSnapshot {
    ClassifierCorrectionResultSnapshot(
        updatedFile: updatedFile,
        ruleDraft: ClassifierRuleDraftSnapshot(
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

private func s304CallLogRecord(id: Int64) -> AiCallLogRecord {
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

private actor S304NoopLister: CoreFileListing {
    func listFiles(repoPath _: String, filter _: FileFilterSnapshot) async throws -> [FileEntrySnapshot] {
        []
    }
}

private actor S304Detailer: CoreFileDetailing {
    let file: FileEntrySnapshot

    init(file: FileEntrySnapshot) {
        self.file = file
    }

    func getFile(repoPath _: String, fileID _: Int64) async throws -> FileEntrySnapshot {
        file
    }
}

private actor S304ChangeLogLister: CoreChangeLogListing {
    func listChanges(repoPath _: String, filter _: ChangeFilterSnapshot) async throws -> [ChangeLogEntrySnapshot] {
        []
    }
}

private struct S304PageErrorMapper: CoreErrorMapping {
    func mapCoreError(_: CoreError) async -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .classify,
            userMessage: "S3-04 apply failed",
            severity: .medium,
            suggestedAction: "Retry apply or classify manually.",
            recoverability: .retryable,
            rawContext: "S3-04 C3-04"
        )
    }
}

private extension RepositoryOpeningResult {
    static func s304Fixture(repoPath: String, files: [FileEntrySnapshot]) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: RepoConfigSnapshot(
                repoPath: repoPath,
                defaultMode: "Copied",
                overviewOutput: "GeneratedOnly",
                aiEnabled: true,
                locale: "zh-Hans",
                iCloudWarn: true,
                enableExtensionRules: true,
                enableKeywordRules: true,
                fallbackToInbox: true,
                allowReplaceDuringImport: false
            ),
            tree: RepositoryTreeNodeSnapshot(
                slug: "__root__",
                displayName: "Repository",
                kind: "RepositoryRoot",
                relativePath: "",
                fileCount: 1,
                depth: 0,
                children: []
            ),
            currentCategoryFiles: files,
            isReadOnly: false,
            writeLockedFileIDs: []
        )
    }
}
