@testable import AreaMatrix
import XCTest

// swiftlint:disable:next type_body_length
final class ChangeCategoryPageFeatureTests: XCTestCase {
    @MainActor
    func testChangeCategoryMoveToCategoryCorePreviewUsesCoreBridgeWithoutMovingFile() async {
        let original = FileEntrySnapshot.changeCategoryFixture(id: 240, name: "contract.pdf")
        let preview = changeCategoryPreview(for: original)
        let mover = ChangeCategoryRecordingMover(previewResult: .success(preview))
        let model = changeCategoryModel(file: original, fileCategoryMover: mover)

        await model.selectFiles([original.id])
        model.beginChangeCategory()
        await model.loadMoveToCategoryPreview(fileID: original.id, targetCategory: "finance")
        let requests = await mover.recordedRequests()

        XCTAssertEqual(requests, [changeCategoryPreviewRequest(fileID: original.id)])
        XCTAssertEqual(model.files, [original])
        XCTAssertEqual(model.selectedFileDetail, original)
        XCTAssertEqual(model.pendingActionDestination, .changeCategory(fileID: original.id))
        XCTAssertEqual(
            model.changeCategoryState,
            .ready(.init(fileID: original.id, targetCategory: "finance"), preview)
        )
    }

    @MainActor
    func testChangeCategoryMoveToCategoryCoreSubmitMoveRefreshesListDetailAndChangeLog() async {
        let original = FileEntrySnapshot.changeCategoryFixture(id: 241, name: "contract.pdf")
        let moved = changeCategoryMovedFile(from: original)
        let preview = changeCategoryPreview(for: original, targetPath: moved.path, targetName: moved.currentName)
        let mover = ChangeCategoryRecordingMover(previewResult: .success(preview), moveResult: .success(moved))
        let logEntry = ChangeLogEntrySnapshot.detailLogFixture(fileID: moved.id, action: "moved")
        let logLister = DetailLogRecordingLister(results: [.success([logEntry])])
        let model = changeCategoryModel(file: original, fileCategoryMover: mover, changeLogLister: logLister)

        await model.selectFiles([original.id])
        model.beginChangeCategory()
        await model.loadMoveToCategoryPreview(fileID: original.id, targetCategory: "finance")
        let didMove = await model.submitMoveToCategory(fileID: original.id, targetCategory: "finance")
        let requests = await mover.recordedRequests()

        XCTAssertTrue(didMove)
        XCTAssertEqual(requests, [
            changeCategoryPreviewRequest(fileID: original.id),
            changeCategoryMoveRequest(fileID: original.id)
        ])
        XCTAssertEqual(model.files, [moved])
        XCTAssertEqual(model.selection, .single(moved.id))
        XCTAssertEqual(model.selectedFileDetail, moved)
        XCTAssertEqual(model.detailLogState, .loaded(fileID: moved.id, entries: [logEntry]))
        XCTAssertEqual(model.detailTabRequest, .automatic(.log))
        XCTAssertNil(model.pendingActionDestination)
        XCTAssertEqual(model.changeCategoryState, .idle)
        XCTAssertEqual(model.statusBanner, .changedCategory(fileID: moved.id, category: "finance"))
    }

    @MainActor
    func testChangeCategoryMoveToCategoryCoreSuccessfulMoveReloadsTargetCategoryAndKeepsFileHighlighted() async {
        let original = FileEntrySnapshot.changeCategoryFixture(id: 243, name: "contract.pdf")
        let moved = changeCategoryMovedFile(from: original, updatedAt: 1_700_000_500)
        let preview = changeCategoryPreview(for: original, targetPath: moved.path, targetName: moved.currentName)
        let mover = ChangeCategoryRecordingMover(previewResult: .success(preview), moveResult: .success(moved))
        let lister = ChangeCategoryRecordingLister(results: [.success([original]), .success([moved])])
        let model = changeCategoryModel(file: original, fileLister: lister, fileCategoryMover: mover)
        var movedCallback: FileEntrySnapshot?

        await model.loadCurrentCategory("docs")
        await model.selectFiles([original.id])
        model.beginChangeCategory()
        await model.loadMoveToCategoryPreview(fileID: original.id, targetCategory: "finance")
        let didMove = await model.submitMoveToCategory(fileID: original.id, targetCategory: "finance") { movedFile in
            movedCallback = movedFile
        }
        await model.loadCurrentCategory(moved.category, focusingOn: moved.id)
        let listRequests = await lister.recordedRequests()

        XCTAssertTrue(didMove)
        XCTAssertEqual(movedCallback, moved)
        XCTAssertEqual(listRequests, [
            FileFilterSnapshot.currentCategory("docs"),
            FileFilterSnapshot.currentCategory("finance")
        ])
        XCTAssertEqual(model.files, [moved])
        XCTAssertEqual(model.selection, .single(moved.id))
        XCTAssertEqual(model.selectedFileDetail, moved)
    }

    @MainActor
    func testChangeCategoryMoveToCategoryCoreContentRefreshUpdatesTreeAndSwitchesToMovedCategory() {
        let moved = FileEntrySnapshot.changeCategoryFixture(
            id: 244,
            path: "finance/contract.pdf",
            category: "finance",
            name: "contract.pdf",
            updatedAt: 1_700_000_600
        )
        let plan = CategoryMoveRefreshPlan.make(
            movedFile: moved,
            currentSidebarID: "docs",
            currentTree: .changeCategoryTree(docsCount: 1, financeCount: 0),
            refreshedTree: .changeCategoryTree(docsCount: 0, financeCount: 1)
        )

        XCTAssertEqual(plan.tree.sidebarRow(id: "docs")?.totalFileCount, 0)
        XCTAssertEqual(plan.tree.sidebarRow(id: "finance")?.totalFileCount, 1)
        XCTAssertEqual(plan.selectedSidebarID, "finance")
        XCTAssertEqual(plan.focusedFileID, moved.id)
        XCTAssertEqual(plan.categoryForFileList, "finance")
    }

    @MainActor
    func testChangeCategoryMoveToCategoryCoreFailureKeepsSheetOpenAndMapsCoreError() async {
        let original = FileEntrySnapshot.changeCategoryFixture(id: 242, name: "blocked.pdf")
        let mapping = CoreErrorMappingSnapshot.changeCategoryClassify()
        let mapper = StaticCoreErrorMapper(mapping: mapping)
        let mover = ChangeCategoryRecordingMover(
            previewResult: .failure(CoreError.Classify(reason: "unknown category"))
        )
        let model = changeCategoryModel(file: original, fileCategoryMover: mover, errorMapper: mapper)

        await model.selectFiles([original.id])
        model.beginChangeCategory()
        await model.loadMoveToCategoryPreview(fileID: original.id, targetCategory: "finance")
        let mappedErrors = await mapper.recordedErrors()

        XCTAssertEqual(model.files, [original])
        XCTAssertEqual(model.selectedFileDetail, original)
        XCTAssertEqual(model.pendingActionDestination, .changeCategory(fileID: original.id))
        XCTAssertEqual(
            model.changeCategoryState,
            .failed(.init(fileID: original.id, targetCategory: "finance"), operation: .preview, mapping)
        )
        XCTAssertEqual(mappedErrors, [CoreError.Classify(reason: "unknown category")])
    }

    @MainActor
    func testChangeCategoryResolveNameConflictCorePreviewKeepsCoreAutoNumberedNameVisibleWithoutMovingFile() async {
        let original = FileEntrySnapshot.changeCategoryFixture(id: 245, name: "contract.pdf")
        let preview = changeCategoryPreview(
            for: original,
            targetPath: "finance/contract_1.pdf",
            targetName: "contract_1.pdf",
            nameConflictResolved: true
        )
        let mover = ChangeCategoryRecordingMover(previewResult: .success(preview))
        let model = changeCategoryModel(file: original, fileCategoryMover: mover)

        await model.selectFiles([original.id])
        model.beginChangeCategory()
        await model.loadMoveToCategoryPreview(fileID: original.id, targetCategory: "finance")
        let requests = await mover.recordedRequests()

        XCTAssertEqual(requests, [changeCategoryPreviewRequest(fileID: original.id)])
        XCTAssertEqual(model.files, [original])
        XCTAssertEqual(
            model.changeCategoryState.preview(for: .init(fileID: original.id, targetCategory: "finance")),
            preview
        )
        XCTAssertTrue(preview.nameConflictResolved)
        XCTAssertEqual(preview.targetName, "contract_1.pdf")
        XCTAssertEqual(preview.targetPath, "finance/contract_1.pdf")
    }

    @MainActor
    func testClassifierCorrectionClassifierCorrectionLoadsRealReasonAndCorePreviewBeforeApply() async {
        let original = FileEntrySnapshot.changeCategoryFixture(id: 246, name: "contract.pdf")
        let reason = ClassifyResultSnapshot.testFixture(
            category: "docs",
            suggestedName: "contract.pdf",
            reason: .extension,
            confidence: 0.93
        )
        let preview = changeCategoryPreview(for: original)
        let predictor = ChangeCategoryRecordingPredictor(result: .success(reason))
        let mover = ChangeCategoryRecordingMover(previewResult: .success(preview))
        let model = changeCategoryModel(
            file: original,
            fileCategoryMover: mover,
            categoryPredictor: predictor
        )

        await model.selectFiles([original.id])
        model.beginClassifierCorrection()
        await model.loadClassifierCorrectionContext(fileID: original.id, filename: original.currentName)
        await model.loadMoveToCategoryPreview(fileID: original.id, targetCategory: "finance")
        let predictionRequests = await predictor.recordedRequests()
        let moveRequests = await mover.recordedRequests()

        XCTAssertEqual(predictionRequests, [
            ChangeCategoryPredictionRequest(repoPath: "/tmp/repo", filename: "contract.pdf")
        ])
        XCTAssertEqual(moveRequests, [
            changeCategoryPreviewRequest(fileID: original.id)
        ])
        XCTAssertEqual(model.classifierCorrectionContextState.result(for: original.id), reason)
        let previewRequest = MainFileCategoryMovePreviewRequest(
            fileID: original.id,
            targetCategory: "finance"
        )
        XCTAssertEqual(model.changeCategoryState.preview(for: previewRequest), preview)
    }

    @MainActor
    // swiftlint:disable:next function_body_length
    func testClassifierCorrectionApplyCorrectionUsesRealCoreBridgeAndReturnedRuleDraft() async {
        let original = FileEntrySnapshot.changeCategoryFixture(id: 247, name: "contract.pdf")
        let corrected = changeCategoryMovedFile(from: original, updatedAt: 1_700_000_800)
        let preview = changeCategoryPreview(
            for: original,
            targetPath: corrected.path,
            targetName: corrected.currentName
        )
        let draft = ClassifierRuleDraftSnapshot.testFixture(
            sourceFileID: original.id,
            targetCategory: "finance",
            keywordCandidates: ["client-a", "contract"],
            extensionCandidates: ["pdf"],
            priority: 42
        )
        let correction = ClassifierCorrectionResultSnapshot.testFixture(
            updatedFile: corrected,
            ruleDraft: draft,
            moveFileRequested: true,
            rememberRequested: true,
            ruleConfirmationRequired: true
        )
        let mover = ChangeCategoryRecordingMover(
            previewResult: .success(preview),
            correctionResult: .success(correction)
        )
        let model = changeCategoryModel(
            file: original,
            fileCategoryMover: mover,
            changeLogLister: DetailLogRecordingLister(results: [.success([])])
        )

        await model.selectFiles([original.id])
        model.beginClassifierCorrection()
        await model.loadMoveToCategoryPreview(fileID: original.id, targetCategory: "finance")
        let didCorrect = await model.submitMoveToCategory(
            fileID: original.id,
            targetCategory: "finance",
            mode: .classifierCorrection,
            options: MainFileCategoryMoveOptions(
                moveFile: true,
                remember: true
            )
        )
        let requests = await mover.recordedRequests()

        XCTAssertTrue(didCorrect)
        XCTAssertEqual(requests, [
            changeCategoryPreviewRequest(fileID: original.id),
            .correction(
                repoPath: "/tmp/repo",
                fileID: original.id,
                targetCategory: "finance",
                moveFile: true,
                remember: true
            )
        ])
        XCTAssertEqual(model.classifierCorrectionResult?.ruleDraft, draft)
        XCTAssertEqual(model.selectedFileDetail, corrected)
        XCTAssertNil(model.pendingActionDestination)
    }

    // swiftlint:disable:next function_body_length
    func testChangeCategoryMoveToCategoryCoreDefaultCoreBridgePreviewsThenMovesCopiedFileAndWritesChangeLog(
    ) async throws {
        let repoURL = try makeChangeCategoryFeatureTemporaryDirectory(prefix: "repo")
        let sourceRoot = try makeChangeCategoryFeatureTemporaryDirectory(prefix: "source")
        defer {
            removeTestTemporaryItems(repoURL, sourceRoot)
        }
        let sourceURL = sourceRoot.appendingPathComponent("contract.pdf")
        try Data("category bytes".utf8).write(to: sourceURL)
        let bridge = CoreBridge()

        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let imported = try await bridge.importCopiedFile(
            repoPath: repoURL.path,
            sourceURL: sourceURL,
            overrideCategory: "docs",
            overrideFilename: "contract.pdf",
            duplicateStrategy: .skip
        )
        let classifierURL = repoURL.appendingPathComponent(".areamatrix/classifier.yaml")
        let classifierBefore = try String(contentsOf: classifierURL)
        let preview = try await bridge.previewMoveToCategory(
            repoPath: repoURL.path,
            fileID: imported.id,
            newCategory: "finance"
        )
        let moved = try await bridge.moveToCategory(repoPath: repoURL.path, fileID: imported.id, newCategory: "finance")
        let detail = try await bridge.getFile(repoPath: repoURL.path, fileID: imported.id)
        let correction = try await bridge.correctFileCategory(
            repoPath: repoURL.path,
            fileID: imported.id,
            targetCategory: "docs",
            moveFile: true,
            remember: true
        )
        let changes = try await bridge.listChanges(repoPath: repoURL.path, filter: .detailLog(fileID: imported.id))

        XCTAssertEqual(preview.fileID, imported.id)
        XCTAssertEqual(preview.fromCategory, "docs")
        XCTAssertEqual(preview.toCategory, "finance")
        XCTAssertEqual(preview.targetPath, "finance/contract.pdf")
        XCTAssertEqual(moved.id, imported.id)
        XCTAssertEqual(moved.category, "finance")
        XCTAssertEqual(detail.path, "finance/contract.pdf")
        XCTAssertEqual(correction.updatedFile.id, imported.id)
        XCTAssertEqual(correction.updatedFile.category, "docs")
        XCTAssertEqual(correction.updatedFile.path, "docs/contract.pdf")
        XCTAssertTrue(correction.moveFileRequested)
        XCTAssertTrue(correction.rememberRequested)
        XCTAssertTrue(correction.ruleConfirmationRequired)
        XCTAssertEqual(correction.ruleDraft?.targetCategory, "docs")
        XCTAssertTrue(correction.ruleDraft?.extensionCandidates.contains("pdf") == true)
        XCTAssertEqual(try String(contentsOf: classifierURL), classifierBefore)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: repoURL.appendingPathComponent("docs/contract.pdf").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: repoURL.appendingPathComponent("finance/contract.pdf").path
        ))
        XCTAssertTrue(changes.contains { $0.action == "moved" })
    }

    func testChangeCategoryResolveNameConflictCoreDefaultCoreBridgePreviewsAutoNumberedTargetNameWithoutMovingFile(
    ) async throws {
        let repoURL = try makeChangeCategoryFeatureTemporaryDirectory(prefix: "repo")
        let sourceRoot = try makeChangeCategoryFeatureTemporaryDirectory(prefix: "source")
        defer {
            removeTestTemporaryItems(repoURL, sourceRoot)
        }
        let financeSourceURL = sourceRoot.appendingPathComponent("finance-contract.pdf")
        let docsSourceURL = sourceRoot.appendingPathComponent("docs-contract.pdf")
        try Data("existing finance bytes".utf8).write(to: financeSourceURL)
        try Data("moving docs bytes".utf8).write(to: docsSourceURL)
        let bridge = CoreBridge()

        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        _ = try await bridge.importCopiedFile(
            repoPath: repoURL.path,
            sourceURL: financeSourceURL,
            overrideCategory: "finance",
            overrideFilename: "contract.pdf",
            duplicateStrategy: .skip
        )
        let movingFile = try await bridge.importCopiedFile(
            repoPath: repoURL.path,
            sourceURL: docsSourceURL,
            overrideCategory: "docs",
            overrideFilename: "contract.pdf",
            duplicateStrategy: .skip
        )

        let preview = try await bridge.previewMoveToCategory(
            repoPath: repoURL.path,
            fileID: movingFile.id,
            newCategory: "finance"
        )

        XCTAssertEqual(preview.fileID, movingFile.id)
        XCTAssertEqual(preview.fromCategory, "docs")
        XCTAssertEqual(preview.toCategory, "finance")
        XCTAssertTrue(preview.nameConflictResolved)
        XCTAssertTrue(preview.targetPath.hasPrefix("finance/"))
        XCTAssertNotEqual(preview.targetPath, "finance/contract.pdf")
        XCTAssertNotEqual(preview.targetName, "contract.pdf")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: repoURL.appendingPathComponent("docs/contract.pdf").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: repoURL.appendingPathComponent("finance/contract.pdf").path
        ))
    }
}
