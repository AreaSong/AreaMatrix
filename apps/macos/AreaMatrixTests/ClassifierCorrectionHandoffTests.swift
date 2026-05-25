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
        let body = s135MirrorDescription(of: ClassifierRuleHandoffRouteView(
            mode: .saveRule,
            handoff: handoff,
            onCancel: {},
            onBack: { _ in },
            onPreviewImpact: { _ in }
        ).body)

        XCTAssertTrue(body.contains("client-a, contract"))
        XCTAssertTrue(body.contains("pdf"))
        XCTAssertTrue(body.contains("42"))
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
    ClassifierRuleHandoff(
        sourcePageID: "S2-16",
        fileID: file.id,
        fileName: file.currentName,
        currentCategory: file.category,
        targetCategory: targetCategory,
        moveFile: true,
        draft: ClassifierRuleDraftSnapshot(
            sourceFileID: file.id,
            targetCategory: targetCategory,
            keywordCandidates: ["client-a", "contract"],
            extensionCandidates: ["pdf"],
            priority: 42
        )
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
