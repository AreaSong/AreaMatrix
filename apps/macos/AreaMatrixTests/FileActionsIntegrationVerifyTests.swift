@testable import AreaMatrix
import XCTest

final class FileActionsIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testRenameFileDeleteFileChangeCategoryFileActionsUseRealCoreAndPreserveUserFileBoundaries() async throws {
        let context = try await makeFileActionsRealCoreContext()
        defer {
            context.cleanUp()
        }

        let renamed = try await assertFileActionRename(context)
        let moved = try await assertFileActionMove(renamed, context)
        try await assertFileActionRemoveIndex(moved, context)
    }

    @MainActor
    private func assertFileActionRename(_ context: FileActionsRealCoreContext) async throws -> FileEntrySnapshot {
        await context.model.loadCurrentCategory("docs")
        await context.model.selectFiles([context.ownedFile.id])
        context.model.beginRename()
        let didRename = await context.model.submitRename(fileID: context.ownedFile.id, newName: "renamed.pdf")
        let renamed = try XCTUnwrap(context.model.selectedFileDetail)

        XCTAssertTrue(didRename)
        XCTAssertEqual(context.model.pendingActionDestination, nil)
        XCTAssertEqual(context.model.renameState, .idle)
        XCTAssertEqual(renamed.id, context.ownedFile.id)
        XCTAssertEqual(renamed.currentName, "renamed.pdf")
        XCTAssertEqual(renamed.category, "docs")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: context.repoURL.appendingPathComponent("docs/renamed.pdf").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: context.repoURL.appendingPathComponent("docs/contract.pdf").path
        ))
        try await assertChangeLogContains(
            "renamed",
            fileID: renamed.id,
            repoURL: context.repoURL,
            bridge: context.bridge
        )
        return renamed
    }

    @MainActor
    private func assertFileActionMove(
        _ renamed: FileEntrySnapshot,
        _ context: FileActionsRealCoreContext
    ) async throws -> FileEntrySnapshot {
        try await assertFileActionMovePreview(renamed, context)
        let didMove = await context.model.submitMoveToCategory(fileID: renamed.id, targetCategory: "finance")
        let moved = try XCTUnwrap(context.model.selectedFileDetail)
        let refreshedTree = try await context.bridge.listTree(repoPath: context.repoURL.path, locale: "zh-Hans")
        let refreshPlan = CategoryMoveRefreshPlan.make(
            movedFile: moved,
            currentSidebarID: "docs",
            currentTree: context.opening.tree,
            refreshedTree: refreshedTree
        )
        await context.model.loadCurrentCategory(refreshPlan.categoryForFileList, focusingOn: moved.id)

        XCTAssertTrue(didMove)
        XCTAssertEqual(context.model.pendingActionDestination, nil)
        XCTAssertEqual(context.model.changeCategoryState, .idle)
        XCTAssertEqual(context.model.selection, .single(moved.id))
        XCTAssertEqual(context.model.selectedFileDetail, moved)
        XCTAssertEqual(refreshPlan.categoryForFileList, "finance")
        XCTAssertEqual(context.model.files.first { $0.id == moved.id }, moved)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: context.repoURL.appendingPathComponent("finance/renamed.pdf").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: context.repoURL.appendingPathComponent("docs/renamed.pdf").path
        ))
        try await assertChangeLogContains(
            "moved",
            fileID: moved.id,
            repoURL: context.repoURL,
            bridge: context.bridge
        )
        return moved
    }

    @MainActor
    private func assertFileActionMovePreview(
        _ renamed: FileEntrySnapshot,
        _ context: FileActionsRealCoreContext
    ) async throws {
        context.model.beginChangeCategory(fileID: renamed.id)
        await context.model.loadMoveToCategoryPreview(fileID: renamed.id, targetCategory: "finance")
        let request = MainFileCategoryMovePreviewRequest(fileID: renamed.id, targetCategory: "finance")
        let preview = try XCTUnwrap(context.model.changeCategoryState.preview(for: request))

        XCTAssertEqual(preview.targetPath, "finance/renamed.pdf")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: context.repoURL.appendingPathComponent("docs/renamed.pdf").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: context.repoURL.appendingPathComponent("finance/renamed.pdf").path
        ))
    }

    @MainActor
    private func assertFileActionRemoveIndex(
        _ moved: FileEntrySnapshot,
        _ context: FileActionsRealCoreContext
    ) async throws {
        await context.model.loadCurrentCategory("docs")
        await context.model.selectFiles([context.indexedFile.id])
        context.model.beginDelete()
        let didDelete = await context.model.submitDelete(fileID: context.indexedFile.id, operation: .removeFromIndex)
        let docsFiles = try await context.bridge.listFiles(
            repoPath: context.repoURL.path,
            filter: .currentCategory("docs")
        )

        XCTAssertTrue(didDelete)
        XCTAssertEqual(context.model.pendingActionDestination, nil)
        XCTAssertEqual(context.model.deleteState, .idle)
        XCTAssertNotEqual(context.model.selectedFileDetail?.id, moved.id)
        XCTAssertFalse(docsFiles.contains { $0.id == context.indexedFile.id })
        XCTAssertEqual(try Data(contentsOf: context.indexedSourceURL), context.indexedSourceBefore)
        XCTAssertTrue(FileManager.default.fileExists(atPath: context.indexedSourceURL.path))
        try await assertChangeLogContains(
            "removed_from_index",
            fileID: context.indexedFile.id,
            repoURL: context.repoURL,
            bridge: context.bridge
        )
    }

    @MainActor
    func testFileActionsIntegrationUsesOnlyDeclaredControlMapActionApis() async {
        let owned = FileEntrySnapshot.fileActionsFixture(id: 310, name: "owned.pdf", storageMode: "Copied")
        let indexed = FileEntrySnapshot.fileActionsFixture(id: 311, name: "indexed.pdf", storageMode: "Indexed")
        let trash = FileEntrySnapshot.fileActionsFixture(id: 312, name: "trash.pdf", storageMode: "Copied")
        let core = FileActionsRecordingCore(files: [owned, indexed, trash])
        let model = MainFileListModel(
            opening: .fileActionsFixture(repoPath: "/tmp/repo", files: [owned, indexed, trash]),
            fileLister: core,
            fileDetailer: core,
            fileRenamer: core,
            fileDeleter: core,
            fileCategoryMover: core,
            changeLogLister: core,
            errorMapper: core
        )

        await model.selectFiles([owned.id])
        model.beginRename()
        let didRename = await model.submitRename(fileID: owned.id, newName: "renamed.pdf")
        model.beginChangeCategory(fileID: owned.id)
        await model.loadMoveToCategoryPreview(fileID: owned.id, targetCategory: "finance")
        let didMove = await model.submitMoveToCategory(fileID: owned.id, targetCategory: "finance")

        model.beginDelete(fileID: indexed.id)
        let didRemoveIndex = await model.submitDelete(fileID: indexed.id, operation: .removeFromIndex)
        model.beginDelete(fileID: trash.id)
        let didMoveToTrash = await model.submitDelete(fileID: trash.id, operation: .moveToTrash)

        XCTAssertTrue(didRename)
        XCTAssertTrue(didMove)
        XCTAssertTrue(didRemoveIndex)
        XCTAssertTrue(didMoveToTrash)
        await core.assertFileActionCalls([
            .rename(fileID: owned.id, newName: "renamed.pdf"),
            .previewMove(fileID: owned.id, targetCategory: "finance"),
            .move(fileID: owned.id, targetCategory: "finance"),
            .removeIndex(fileID: indexed.id),
            .delete(fileID: trash.id)
        ])
    }
}
