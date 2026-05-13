@testable import AreaMatrix
import XCTest

final class FileActionsIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testS133S134S135FileActionsUseRealCoreAndPreserveUserFileBoundaries() async throws {
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
        await context.model.submitRename(fileID: context.ownedFile.id, newName: "renamed.pdf")
        let renamed = try XCTUnwrap(context.model.selectedFileDetail)

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
        await context.model.submitMoveToCategory(fileID: renamed.id, targetCategory: "finance")
        let moved = try XCTUnwrap(context.model.selectedFileDetail)
        let refreshedTree = try await context.bridge.listTree(repoPath: context.repoURL.path, locale: "zh-Hans")
        let refreshPlan = CategoryMoveRefreshPlan.make(
            movedFile: moved,
            currentSidebarID: "docs",
            currentTree: context.opening.tree,
            refreshedTree: refreshedTree
        )
        await context.model.loadCurrentCategory(refreshPlan.categoryForFileList, focusingOn: moved.id)

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
        await context.model.submitDelete(fileID: context.indexedFile.id, operation: .removeFromIndex)
        let docsFiles = try await context.bridge.listFiles(
            repoPath: context.repoURL.path,
            filter: .currentCategory("docs")
        )

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
        await model.submitRename(fileID: owned.id, newName: "renamed.pdf")
        model.beginChangeCategory(fileID: owned.id)
        await model.loadMoveToCategoryPreview(fileID: owned.id, targetCategory: "finance")
        await model.submitMoveToCategory(fileID: owned.id, targetCategory: "finance")

        model.beginDelete(fileID: indexed.id)
        await model.submitDelete(fileID: indexed.id, operation: .removeFromIndex)
        model.beginDelete(fileID: trash.id)
        await model.submitDelete(fileID: trash.id, operation: .moveToTrash)

        let calls = await core.recordedActionCalls()

        XCTAssertEqual(calls, [
            .rename(fileID: owned.id, newName: "renamed.pdf"),
            .previewMove(fileID: owned.id, targetCategory: "finance"),
            .move(fileID: owned.id, targetCategory: "finance"),
            .removeIndex(fileID: indexed.id),
            .delete(fileID: trash.id)
        ])
        XCTAssertTrue(calls.allSatisfy(\.isDeclaredFileActionCapability))
    }
}

private struct FileActionsRealCoreContext {
    var repoURL: URL
    var sourceRootURL: URL
    var indexedSourceURL: URL
    var indexedSourceBefore: Data
    var bridge: CoreBridge
    var opening: RepositoryOpeningResult
    var model: MainFileListModel
    var ownedFile: FileEntrySnapshot
    var indexedFile: FileEntrySnapshot

    func cleanUp() {
        try? FileManager.default.removeItem(at: repoURL)
        try? FileManager.default.removeItem(at: sourceRootURL)
    }
}

private enum FileActionsCoreCall: Equatable {
    case rename(fileID: Int64, newName: String)
    case previewMove(fileID: Int64, targetCategory: String)
    case move(fileID: Int64, targetCategory: String)
    case removeIndex(fileID: Int64)
    case delete(fileID: Int64)

    var isDeclaredFileActionCapability: Bool {
        switch self {
        case .rename, .delete, .removeIndex, .previewMove, .move:
            true
        }
    }
}

private actor FileActionsRecordingCore: CoreFileListing,
    CoreFileDetailing,
    CoreFileRenaming,
    CoreFileDeleting,
    CoreFileCategoryMoving,
    CoreChangeLogListing,
    CoreErrorMapping {
    private var filesByID: [Int64: FileEntrySnapshot]
    private var calls: [FileActionsCoreCall] = []

    init(files: [FileEntrySnapshot]) {
        filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
    }

    func listFiles(repoPath _: String, filter: FileFilterSnapshot) async throws -> [FileEntrySnapshot] {
        filesByID.values
            .filter { filter.category == nil || $0.category == filter.category }
            .sorted { $0.id < $1.id }
    }

    func getFile(repoPath _: String, fileID: Int64) async throws -> FileEntrySnapshot {
        guard let file = filesByID[fileID] else {
            throw CoreError.FileNotFound(path: "\(fileID)")
        }
        return file
    }

    func renameFile(repoPath: String, fileID: Int64, newName: String) async throws -> FileEntrySnapshot {
        calls.append(.rename(fileID: fileID, newName: newName))
        var file = try await getFile(repoPath: repoPath, fileID: fileID)
        file.currentName = newName
        file.path = "\(file.path.split(separator: "/").dropLast().joined(separator: "/"))/\(newName)"
        filesByID[fileID] = file
        return file
    }

    func deleteFile(repoPath _: String, fileID: Int64) async throws {
        calls.append(.delete(fileID: fileID))
        filesByID.removeValue(forKey: fileID)
    }

    func removeIndexEntry(repoPath _: String, fileID: Int64) async throws {
        calls.append(.removeIndex(fileID: fileID))
        filesByID.removeValue(forKey: fileID)
    }

    func previewMoveToCategory(
        repoPath: String,
        fileID: Int64,
        newCategory: String
    ) async throws -> MoveToCategoryPreviewSnapshot {
        calls.append(.previewMove(fileID: fileID, targetCategory: newCategory))
        let file = try await getFile(repoPath: repoPath, fileID: fileID)
        return MoveToCategoryPreviewSnapshot(
            fileID: file.id,
            fromCategory: file.category,
            toCategory: newCategory,
            currentPath: file.path,
            targetPath: "\(newCategory)/\(file.currentName)",
            targetName: file.currentName,
            storageMode: file.storageMode,
            indexOnly: file.storageMode == "Indexed",
            nameConflictResolved: false,
            willMoveFile: file.storageMode != "Indexed"
        )
    }

    func moveToCategory(repoPath: String, fileID: Int64, newCategory: String) async throws -> FileEntrySnapshot {
        calls.append(.move(fileID: fileID, targetCategory: newCategory))
        var file = try await getFile(repoPath: repoPath, fileID: fileID)
        file.category = newCategory
        file.path = "\(newCategory)/\(file.currentName)"
        filesByID[fileID] = file
        return file
    }

    func listChanges(repoPath _: String, filter _: ChangeFilterSnapshot) async throws -> [ChangeLogEntrySnapshot] {
        []
    }

    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .internal,
            userMessage: "\(error)",
            severity: .high,
            suggestedAction: "Retry the file action.",
            recoverability: .retryable,
            rawContext: "2-3/task-37 file-actions integration verify"
        )
    }

    func recordedActionCalls() -> [FileActionsCoreCall] {
        calls
    }
}

private extension RepositoryOpeningResult {
    static func fileActionsFixture(repoPath: String, files: [FileEntrySnapshot]) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: RepoConfigSnapshot(
                repoPath: repoPath,
                defaultMode: "Copied",
                overviewOutput: "GeneratedOnly",
                aiEnabled: false,
                locale: "zh-Hans",
                iCloudWarn: true,
                enableExtensionRules: true,
                enableKeywordRules: true,
                fallbackToInbox: true,
                allowReplaceDuringImport: false
            ),
            tree: .fileActionsTree(docsCount: Int64(files.count), financeCount: 0),
            currentCategoryFiles: files
        )
    }
}

private extension RepositoryTreeNodeSnapshot {
    static func fileActionsTree(docsCount: Int64, financeCount: Int64) -> RepositoryTreeNodeSnapshot {
        RepositoryTreeNodeSnapshot(
            slug: "__root__",
            displayName: "Repository",
            kind: "RepositoryRoot",
            relativePath: "",
            fileCount: 0,
            depth: 0,
            children: [
                RepositoryTreeNodeSnapshot(slug: "docs", displayName: "docs", fileCount: docsCount, children: []),
                RepositoryTreeNodeSnapshot(
                    slug: "finance",
                    displayName: "finance",
                    fileCount: financeCount,
                    children: []
                )
            ]
        )
    }
}

private extension FileEntrySnapshot {
    static func fileActionsFixture(id: Int64, name: String, storageMode: String) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: "docs/\(name)",
            originalName: name,
            currentName: name,
            category: "docs",
            sizeBytes: 128,
            hashSha256: "file-actions-\(id)",
            storageMode: storageMode,
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000,
            updatedAt: 1_700_000_100
        )
    }
}

private func makeFileActionsOpening(
    repoURL: URL,
    bridge: CoreBridge,
    category: String
) async throws -> RepositoryOpeningResult {
    let config = try await bridge.loadConfig(repoPath: repoURL.path)
    let tree = try await bridge.listTree(repoPath: repoURL.path, locale: "zh-Hans")
    let files = try await bridge.listFiles(repoPath: repoURL.path, filter: .currentCategory(category))
    return RepositoryOpeningResult(config: config, tree: tree, currentCategoryFiles: files)
}

@MainActor
private func makeFileActionsRealCoreContext() async throws -> FileActionsRealCoreContext {
    let repoURL = try makeFileActionsTemporaryDirectory(prefix: "repo")
    let sourceRootURL = try makeFileActionsTemporaryDirectory(prefix: "source")
    let ownedSourceURL = sourceRootURL.appendingPathComponent("contract.pdf")
    let indexedSourceURL = sourceRootURL.appendingPathComponent("external.pdf")
    try Data("owned bytes".utf8).write(to: ownedSourceURL)
    try Data("indexed bytes".utf8).write(to: indexedSourceURL)
    let indexedSourceBefore = try Data(contentsOf: indexedSourceURL)

    let bridge = CoreBridge()
    try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
    let owned = try await bridge.importCopiedFile(
        repoPath: repoURL.path,
        sourceURL: ownedSourceURL,
        overrideCategory: "docs",
        overrideFilename: "contract.pdf",
        duplicateStrategy: .skip
    )
    let indexed = try await bridge.importIndexedFile(
        repoPath: repoURL.path,
        sourceURL: indexedSourceURL,
        overrideCategory: "docs",
        overrideFilename: "external.pdf",
        duplicateStrategy: .skip
    )

    let opening = try await makeFileActionsOpening(repoURL: repoURL, bridge: bridge, category: "docs")
    let model = MainFileListModel(
        opening: opening,
        fileLister: bridge,
        fileDetailer: bridge,
        fileRenamer: bridge,
        fileDeleter: bridge,
        fileCategoryMover: bridge,
        changeLogLister: bridge,
        errorMapper: bridge
    )

    return FileActionsRealCoreContext(
        repoURL: repoURL,
        sourceRootURL: sourceRootURL,
        indexedSourceURL: indexedSourceURL,
        indexedSourceBefore: indexedSourceBefore,
        bridge: bridge,
        opening: opening,
        model: model,
        ownedFile: owned,
        indexedFile: indexed
    )
}

private func assertChangeLogContains(
    _ action: String,
    fileID: Int64,
    repoURL: URL,
    bridge: CoreBridge
) async throws {
    let changes = try await bridge.listChanges(repoPath: repoURL.path, filter: .detailLog(fileID: fileID))
    XCTAssertTrue(changes.contains { $0.action == action })
}

private func makeFileActionsTemporaryDirectory(prefix: String) throws -> URL {
    let name = "AreaMatrixFileActions-\(prefix)-\(UUID().uuidString)"
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
