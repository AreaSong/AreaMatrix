@testable import AreaMatrix
import XCTest

final class ClassifierCorrectionHandoffTests: XCTestCase {
    @MainActor
    func testClassifierCorrectionRememberRuleRoutesToSaveAndPreviewHandoffsWithoutCallingMutationCore() async {
        let file = classifierCorrectionFile(id: 260, name: "contract.pdf")
        let mover = ClassifierCorrectionNoopCategoryMover()
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [file]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(file)),
            fileCategoryMover: mover,
            errorMapper: DetailMetaErrorMapper(mapping: classifierCorrectionClassifierCorrectionClassifyMapping())
        )

        await model.selectFiles([file.id])
        model.beginClassifierCorrection()
        model.beginClassifierRuleHandoff(
            fileID: file.id,
            targetCategory: "finance",
            moveFile: true,
            destination: .saveRule
        )
        XCTAssertEqual(model.pendingActionDestination?.pageID, "classifier-rule-save")
        guard case let .saveRule(saveHandoff) = model.pendingActionDestination?.classifierRuleRoute else {
            return XCTFail("Expected classifier-rule-save save-rule handoff")
        }
        assertClassifierCorrectionHandoff(saveHandoff, file: file, targetCategory: "finance")
        XCTAssertEqual(model.selectedFileDetail, file)
        XCTAssertEqual(model.files, [file])
        XCTAssertNil(model.classifierCorrectionResult)

        model.beginClassifierRuleHandoff(
            fileID: file.id,
            targetCategory: "finance",
            moveFile: true,
            destination: .impactPreview
        )
        XCTAssertEqual(model.pendingActionDestination?.pageID, "classifier-impact-preview")
        guard case let .impactPreview(previewHandoff) = model.pendingActionDestination?.classifierRuleRoute else {
            return XCTFail("Expected classifier-impact-preview impact-preview handoff")
        }
        assertClassifierCorrectionHandoff(previewHandoff, file: file, targetCategory: "finance")
        XCTAssertEqual(model.selectedFileDetail, file)
        XCTAssertEqual(model.files, [file])
        XCTAssertNil(model.classifierCorrectionResult)
        let recordedRequests = await mover.recordedRequests()
        XCTAssertEqual(recordedRequests, [])
    }

    @MainActor
    func testClassifierCorrectionHandoffSummaryDisplaysCoreRuleDraftWithoutSyntheticCandidates() {
        let draft = ClassifierRuleDraftSnapshot(
            sourceFileID: 260,
            targetCategory: "finance",
            keywordCandidates: ["client-a", "contract"],
            extensionCandidates: ["pdf"],
            priority: 42
        )
        let handoff = ClassifierRuleHandoff(
            sourcePageID: "classifier-correction",
            fileID: 260,
            fileName: "contract.pdf",
            currentCategory: "docs",
            targetCategory: "finance",
            moveFile: true,
            draft: draft
        )
        let values = handoff.summaryRows.map(\.value)

        XCTAssertTrue(values.contains("client-a, contract"))
        XCTAssertTrue(values.contains("pdf"))
        XCTAssertTrue(values.contains("42"))
    }

    @MainActor
    func testClassifierRuleSaveRuleSaveModelNormalizesExtensionAndRequiresPreviewForExtensionOnlyRule() {
        let file = classifierCorrectionFile(id: 261, name: "Contract.PDF")
        var model = ClassifierRuleSaveSheetModel(handoff: classifierCorrectionHandoff(
            file: file,
            targetCategory: "finance",
            selectedKeywords: [],
            selectedExtensions: [".PDF"],
            previewConfirmed: false
        ))

        XCTAssertEqual(model.selectedKeywords, [])
        XCTAssertEqual(model.selectedExtensions, ["pdf"])
        XCTAssertEqual(model.priority, 42)
        XCTAssertEqual(model.validationMessage, "Extension-only rules must be previewed before saving.")
        XCTAssertFalse(model.canSave)
        XCTAssertEqual(model.saveRequest.extensions, ["pdf"])
        XCTAssertFalse(model.saveRequest.previewConfirmed)

        model.setKeyword("contract", isSelected: true)

        XCTAssertNil(model.validationMessage)
        XCTAssertTrue(model.canSave)
        XCTAssertEqual(model.saveRequest.keywords, ["contract"])
        XCTAssertEqual(model.saveRequest.extensions, ["pdf"])
    }

    @MainActor
    func testClassifierRuleSaveCompletesSaveRuleRouteWithSavedStatusBanner() async {
        let file = classifierCorrectionFile(id: 262, name: "contract.pdf")
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [file]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(file)),
            errorMapper: DetailMetaErrorMapper(mapping: classifierCorrectionClassifierCorrectionClassifyMapping())
        )

        await model.selectFiles([file.id])
        model.beginClassifierCorrection()
        model.beginClassifierRuleHandoff(
            fileID: file.id,
            targetCategory: "finance",
            moveFile: true,
            destination: .saveRule
        )
        model.completeClassifierRuleSave(ClassifierRuleSnapshot(
            targetCategory: "finance",
            keywords: ["contract"],
            extensions: ["pdf"],
            priority: 0,
            previewConfirmed: false
        ))

        XCTAssertNil(model.pendingActionDestination)
        XCTAssertEqual(model.statusBanner, .savedClassifierRule(category: "finance"))
        XCTAssertEqual(
            model.statusBanner?.message,
            "Classification rule saved for finance. Future classification uses the updated classifier config."
        )
    }

    func testClassifierRuleSaveDefaultCoreBridgeSavesClassifierRuleWithoutTouchingImportedFile() async throws {
        let repoURL = try makeImportSingleFileTemporaryDirectory(prefix: "classifierRuleSave-repo")
        let sourceRoot = try makeImportSingleFileTemporaryDirectory(prefix: "classifierRuleSave-source")
        defer {
            try? FileManager.default.removeItem(at: repoURL)
            try? FileManager.default.removeItem(at: sourceRoot)
        }
        let sourceURL = sourceRoot.appendingPathComponent("contract-classifierRuleSave.txt")
        try Data("rule-save bytes".utf8).write(to: sourceURL)
        let bridge = CoreBridge()

        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let imported = try await bridge.importCopiedFile(
            repoPath: repoURL.path,
            sourceURL: sourceURL,
            overrideCategory: "docs",
            overrideFilename: "contract-classifierRuleSave.txt",
            duplicateStrategy: .skip
        )
        let classifierURL = repoURL.appendingPathComponent(".areamatrix/classifier.yaml")
        let saved = try await bridge.saveClassifierRule(
            repoPath: repoURL.path,
            rule: ClassifierRuleSnapshot(
                targetCategory: "finance",
                keywords: ["contract-classifierRuleSave"],
                extensions: [],
                priority: 0,
                previewConfirmed: false
            )
        )
        let classifierText = try String(contentsOf: classifierURL)
        let detail = try await bridge.getFile(repoPath: repoURL.path, fileID: imported.id)

        XCTAssertEqual(saved.targetCategory, "finance")
        XCTAssertEqual(saved.keywords, ["contract-classifierRuleSave"])
        XCTAssertTrue(classifierText.contains("contract-classifierRuleSave"))
        XCTAssertEqual(detail.id, imported.id)
        XCTAssertEqual(detail.category, "docs")
        XCTAssertEqual(detail.path, "docs/contract-classifierRuleSave.txt")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: repoURL.appendingPathComponent("docs/contract-classifierRuleSave.txt").path
        ))
    }

    @MainActor
    func testClassifierImpactPreviewPreviewModelBuildsRuleDraftRequestAndFiltersReportRows() {
        let file = classifierCorrectionFile(id: 263, name: "contract.pdf")
        var model = ClassifierImpactPreviewSheetModel(handoff: classifierCorrectionHandoff(file: file, targetCategory: "finance"))
        let request = model.request

        XCTAssertEqual(request.mode, .ruleDraft)
        XCTAssertEqual(request.rule.targetCategory, "finance")
        XCTAssertEqual(request.rule.keywords, ["client-a"])
        XCTAssertEqual(request.rule.extensions, ["pdf"])
        XCTAssertTrue(request.moveFiles)
        XCTAssertNil(request.replacementCategory)

        model.markLoaded(classifierImpactPreviewReport(request: request))
        XCTAssertEqual(model.emptyStateText, nil)
        XCTAssertEqual(model.filteredSamples.map(\.status), [.willUpdate, .alreadyCorrect, .indexOnly])

        model.filter = .willUpdate
        XCTAssertEqual(model.filteredSamples.map(\.fileID), [263])

        model.filter = .skipped
        XCTAssertEqual(model.filteredSamples.map(\.status), [.alreadyCorrect, .indexOnly])
    }

    func testClassifierImpactPreviewDefaultCoreBridgePreviewsImpactWithoutSavingRuleOrChangingExistingFile() async throws {
        let repoURL = try makeImportSingleFileTemporaryDirectory(prefix: "classifierImpactPreview-repo")
        let sourceRoot = try makeImportSingleFileTemporaryDirectory(prefix: "classifierImpactPreview-source")
        defer {
            try? FileManager.default.removeItem(at: repoURL)
            try? FileManager.default.removeItem(at: sourceRoot)
        }
        let sourceURL = sourceRoot.appendingPathComponent("contract-classifierImpactPreview.txt")
        try Data("impact preview bytes".utf8).write(to: sourceURL)
        let bridge = CoreBridge()

        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let imported = try await bridge.importCopiedFile(
            repoPath: repoURL.path,
            sourceURL: sourceURL,
            overrideCategory: "docs",
            overrideFilename: "contract-classifierImpactPreview.txt",
            duplicateStrategy: .skip
        )
        let classifierURL = repoURL.appendingPathComponent(".areamatrix/classifier.yaml")
        let classifierBefore = try String(contentsOf: classifierURL)
        let report = try await bridge.previewClassifierRuleImpact(
            repoPath: repoURL.path,
            request: ClassifierImpactPreviewRequestSnapshot(
                mode: .ruleDraft,
                rule: ClassifierRuleSnapshot(
                    targetCategory: "finance",
                    keywords: ["contract"],
                    extensions: [],
                    priority: 100,
                    previewConfirmed: false
                ),
                moveFiles: false,
                replacementCategory: nil
            )
        )
        let classifierAfter = try String(contentsOf: classifierURL)
        let detail = try await bridge.getFile(repoPath: repoURL.path, fileID: imported.id)

        XCTAssertEqual(report.request.rule.keywords, ["contract"])
        XCTAssertEqual(report.affectedFileCount, 1)
        XCTAssertEqual(report.willUpdateCount, 1)
        XCTAssertEqual(report.samples.first?.fileID, imported.id)
        XCTAssertEqual(report.samples.first?.status, .willUpdate)
        XCTAssertEqual(classifierAfter, classifierBefore)
        XCTAssertEqual(detail.category, "docs")
        XCTAssertEqual(detail.path, "docs/contract-classifierImpactPreview.txt")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: repoURL.appendingPathComponent("docs/contract-classifierImpactPreview.txt").path
        ))
    }
}

private actor ClassifierCorrectionNoopCategoryMover: CoreFileCategoryMoving {
    private var requests: [String] = []

    func previewMoveToCategory(
        repoPath _: String,
        fileID _: Int64,
        newCategory _: String
    ) async throws -> MoveToCategoryPreviewSnapshot {
        requests.append("preview")
        throw CoreError.Internal(message: "unexpected preview")
    }

    func moveToCategory(repoPath _: String, fileID _: Int64, newCategory _: String) async throws -> FileEntrySnapshot {
        requests.append("move")
        throw CoreError.Internal(message: "unexpected move")
    }

    func correctFileCategory(
        repoPath _: String,
        fileID _: Int64,
        targetCategory _: String,
        moveFile _: Bool,
        remember _: Bool
    ) async throws -> ClassifierCorrectionResultSnapshot {
        requests.append("correction")
        throw CoreError.Internal(message: "unexpected correction")
    }

    func recordedRequests() -> [String] {
        requests
    }
}

private func assertClassifierCorrectionHandoff(
    _ handoff: ClassifierRuleHandoff,
    file: FileEntrySnapshot,
    targetCategory: String
) {
    XCTAssertEqual(handoff.sourcePageID, "classifier-correction")
    XCTAssertEqual(handoff.fileID, file.id)
    XCTAssertEqual(handoff.fileName, file.currentName)
    XCTAssertEqual(handoff.currentCategory, file.category)
    XCTAssertEqual(handoff.targetCategory, targetCategory)
    XCTAssertTrue(handoff.moveFile)
    XCTAssertEqual(handoff.draft.sourceFileID, file.id)
    XCTAssertEqual(handoff.draft.targetCategory, targetCategory)
    XCTAssertTrue(handoff.draft.keywordCandidates.contains("contract"))
    XCTAssertTrue(handoff.draft.extensionCandidates.contains("pdf"))
}

private func classifierCorrectionFile(id: Int64, name: String) -> FileEntrySnapshot {
    FileEntrySnapshot(
        id: id,
        path: "docs/contracts/\(name)",
        originalName: name,
        currentName: name,
        category: "docs",
        sizeBytes: 512,
        hashSha256: "classifierCorrection-\(id)",
        storageMode: "Copied",
        origin: "Imported",
        sourcePath: nil,
        importedAt: 1_700_000_000,
        updatedAt: 1_700_000_100
    )
}

private func classifierCorrectionHandoff(file: FileEntrySnapshot, targetCategory: String) -> ClassifierRuleHandoff {
    classifierCorrectionHandoff(
        file: file,
        targetCategory: targetCategory,
        selectedKeywords: ["client-a"],
        selectedExtensions: ["pdf"],
        previewConfirmed: false
    )
}

private func classifierCorrectionHandoff(
    file: FileEntrySnapshot,
    targetCategory: String,
    selectedKeywords: [String],
    selectedExtensions: [String],
    previewConfirmed: Bool
) -> ClassifierRuleHandoff {
    ClassifierRuleHandoff(
        sourcePageID: "classifier-correction",
        fileID: file.id,
        fileName: file.currentName,
        sourcePath: file.sourcePath ?? file.path,
        currentCategory: file.category,
        targetCategory: targetCategory,
        moveFile: true,
        draft: ClassifierRuleDraftSnapshot(
            sourceFileID: file.id,
            targetCategory: targetCategory,
            keywordCandidates: ["client-a", "contract"],
            extensionCandidates: ["pdf"],
            priority: 42
        ),
        selectedKeywords: selectedKeywords,
        selectedExtensions: selectedExtensions,
        previewConfirmed: previewConfirmed
    )
}

private func classifierCorrectionClassifierCorrectionClassifyMapping() -> CoreErrorMappingSnapshot {
    CoreErrorMappingSnapshot(
        kind: .classify,
        userMessage: "Target category is unavailable.",
        severity: .medium,
        suggestedAction: "Choose another category, then retry.",
        recoverability: .userActionRequired,
        rawContext: "classifier-correction classifier-correction-core correct_file_category"
    )
}

private func classifierImpactPreviewReport(request: ClassifierImpactPreviewRequestSnapshot) -> RuleImpactReportSnapshot {
    RuleImpactReportSnapshot(
        request: request,
        affectedFileCount: 3,
        willUpdateCount: 1,
        alreadyCorrectCount: 1,
        needsReviewCount: 1,
        conflictCount: 0,
        sampleLimit: 50,
        samples: [
            classifierImpactPreviewSample(fileID: 263, status: .willUpdate),
            classifierImpactPreviewSample(fileID: 264, status: .alreadyCorrect),
            classifierImpactPreviewSample(fileID: 265, status: .indexOnly)
        ],
        conflicts: [],
        needsReview: true,
        warningRequired: false,
        warning: nil,
        canApply: false,
        applyBlockedReason: "Resolve review items before applying."
    )
}

private func classifierImpactPreviewSample(fileID: Int64, status: RuleImpactStatusSnapshot) -> RuleImpactSampleSnapshot {
    RuleImpactSampleSnapshot(
        fileID: fileID,
        path: "docs/contract-\(fileID).pdf",
        currentCategory: "docs",
        newCategory: "finance",
        matchReasons: [.keyword],
        status: status,
        reason: nil
    )
}
