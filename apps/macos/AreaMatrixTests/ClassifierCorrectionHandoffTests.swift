@testable import AreaMatrix
import XCTest

final class ClassifierCorrectionHandoffTests: XCTestCase {
    @MainActor
    func testS216RememberRuleRoutesToSaveAndPreviewHandoffsWithoutCallingMutationCore() async {
        let file = s216File(id: 260, name: "contract.pdf")
        let mover = S216NoopCategoryMover()
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [file]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(file)),
            fileCategoryMover: mover,
            errorMapper: DetailMetaErrorMapper(mapping: s216ClassifierCorrectionClassifyMapping())
        )

        await model.selectFiles([file.id])
        model.beginClassifierCorrection()
        model.beginClassifierRuleHandoff(
            fileID: file.id,
            targetCategory: "finance",
            moveFile: true,
            destination: .saveRule
        )
        XCTAssertEqual(model.pendingActionDestination?.pageID, "S2-17")
        guard case let .saveRule(saveHandoff) = model.pendingActionDestination?.classifierRuleRoute else {
            return XCTFail("Expected S2-17 save-rule handoff")
        }
        assertS216Handoff(saveHandoff, file: file, targetCategory: "finance")
        XCTAssertEqual(model.selectedFileDetail, file)
        XCTAssertEqual(model.files, [file])
        XCTAssertNil(model.classifierCorrectionResult)

        model.beginClassifierRuleHandoff(
            fileID: file.id,
            targetCategory: "finance",
            moveFile: true,
            destination: .impactPreview
        )
        XCTAssertEqual(model.pendingActionDestination?.pageID, "S2-18")
        guard case let .impactPreview(previewHandoff) = model.pendingActionDestination?.classifierRuleRoute else {
            return XCTFail("Expected S2-18 impact-preview handoff")
        }
        assertS216Handoff(previewHandoff, file: file, targetCategory: "finance")
        XCTAssertEqual(model.selectedFileDetail, file)
        XCTAssertEqual(model.files, [file])
        XCTAssertNil(model.classifierCorrectionResult)
        let recordedRequests = await mover.recordedRequests()
        XCTAssertEqual(recordedRequests, [])
    }

    @MainActor
    func testS216HandoffSummaryDisplaysCoreRuleDraftWithoutSyntheticCandidates() {
        let draft = ClassifierRuleDraftSnapshot(
            sourceFileID: 260,
            targetCategory: "finance",
            keywordCandidates: ["client-a", "contract"],
            extensionCandidates: ["pdf"],
            priority: 42
        )
        let handoff = ClassifierRuleHandoff(
            sourcePageID: "S2-16",
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
    func testS217RuleSaveModelNormalizesExtensionAndRequiresPreviewForExtensionOnlyRule() {
        let file = s216File(id: 261, name: "Contract.PDF")
        var model = ClassifierRuleSaveSheetModel(handoff: s216Handoff(
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
    func testS217CompletesSaveRuleRouteWithSavedStatusBanner() async {
        let file = s216File(id: 262, name: "contract.pdf")
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [file]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(file)),
            errorMapper: DetailMetaErrorMapper(mapping: s216ClassifierCorrectionClassifyMapping())
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

    func testS217DefaultCoreBridgeSavesClassifierRuleWithoutTouchingImportedFile() async throws {
        let repoURL = try makeImportSingleFileTemporaryDirectory(prefix: "s217-repo")
        let sourceRoot = try makeImportSingleFileTemporaryDirectory(prefix: "s217-source")
        defer {
            try? FileManager.default.removeItem(at: repoURL)
            try? FileManager.default.removeItem(at: sourceRoot)
        }
        let sourceURL = sourceRoot.appendingPathComponent("contract-s217.txt")
        try Data("rule-save bytes".utf8).write(to: sourceURL)
        let bridge = CoreBridge()

        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let imported = try await bridge.importCopiedFile(
            repoPath: repoURL.path,
            sourceURL: sourceURL,
            overrideCategory: "docs",
            overrideFilename: "contract-s217.txt",
            duplicateStrategy: .skip
        )
        let classifierURL = repoURL.appendingPathComponent(".areamatrix/classifier.yaml")
        let saved = try await bridge.saveClassifierRule(
            repoPath: repoURL.path,
            rule: ClassifierRuleSnapshot(
                targetCategory: "finance",
                keywords: ["contract-s217"],
                extensions: [],
                priority: 0,
                previewConfirmed: false
            )
        )
        let classifierText = try String(contentsOf: classifierURL)
        let detail = try await bridge.getFile(repoPath: repoURL.path, fileID: imported.id)

        XCTAssertEqual(saved.targetCategory, "finance")
        XCTAssertEqual(saved.keywords, ["contract-s217"])
        XCTAssertTrue(classifierText.contains("contract-s217"))
        XCTAssertEqual(detail.id, imported.id)
        XCTAssertEqual(detail.category, "docs")
        XCTAssertEqual(detail.path, "docs/contract-s217.txt")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: repoURL.appendingPathComponent("docs/contract-s217.txt").path
        ))
    }
}

private actor S216NoopCategoryMover: CoreFileCategoryMoving {
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

private func assertS216Handoff(
    _ handoff: ClassifierRuleHandoff,
    file: FileEntrySnapshot,
    targetCategory: String
) {
    XCTAssertEqual(handoff.sourcePageID, "S2-16")
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

private func s216File(id: Int64, name: String) -> FileEntrySnapshot {
    FileEntrySnapshot(
        id: id,
        path: "docs/contracts/\(name)",
        originalName: name,
        currentName: name,
        category: "docs",
        sizeBytes: 512,
        hashSha256: "s216-\(id)",
        storageMode: "Copied",
        origin: "Imported",
        sourcePath: nil,
        importedAt: 1_700_000_000,
        updatedAt: 1_700_000_100
    )
}

private func s216Handoff(file: FileEntrySnapshot, targetCategory: String) -> ClassifierRuleHandoff {
    s216Handoff(
        file: file,
        targetCategory: targetCategory,
        selectedKeywords: ["client-a"],
        selectedExtensions: ["pdf"],
        previewConfirmed: false
    )
}

private func s216Handoff(
    file: FileEntrySnapshot,
    targetCategory: String,
    selectedKeywords: [String],
    selectedExtensions: [String],
    previewConfirmed: Bool
) -> ClassifierRuleHandoff {
    ClassifierRuleHandoff(
        sourcePageID: "S2-16",
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

private func s216ClassifierCorrectionClassifyMapping() -> CoreErrorMappingSnapshot {
    CoreErrorMappingSnapshot(
        kind: .classify,
        userMessage: "Target category is unavailable.",
        severity: .medium,
        suggestedAction: "Choose another category, then retry.",
        recoverability: .userActionRequired,
        rawContext: "S2-16 C2-12 correct_file_category"
    )
}
