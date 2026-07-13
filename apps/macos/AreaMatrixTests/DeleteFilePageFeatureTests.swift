@testable import AreaMatrix
import XCTest

final class DeleteFilePageFeatureTests: XCTestCase {
    @MainActor
    func testDeleteFileDeleteRemoveIndexCoreMoveToTrashUsesCoreBridgeAndClearsSelection() async {
        let file = FileEntrySnapshot.deleteFixture(id: 230, name: "owned.pdf", storageMode: "Copied")
        let deleter = DeleteRecordingDeleter()
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [file]),
            fileLister: NoopFileLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(file)),
            fileDeleter: deleter,
            changeLogLister: DetailLogRecordingLister(results: [.success([])]),
            errorMapper: StaticCoreErrorMapper(mapping: .deleteIo())
        )

        await model.selectFiles([file.id])
        model.beginDelete()
        let didDelete = await model.submitDelete(fileID: file.id, operation: .moveToTrash)

        XCTAssertTrue(didDelete)
        await deleter.assertFileDeletionRequests([.delete(repoPath: "/tmp/repo", fileID: file.id)])
        XCTAssertEqual(model.files, [])
        XCTAssertEqual(model.selection, .none)
        XCTAssertNil(model.selectedFileDetail)
        XCTAssertNil(model.pendingActionDestination)
        XCTAssertEqual(model.deleteState, .idle)
        XCTAssertEqual(model.statusBanner, .movedFileToTrash(fileID: file.id))
    }

    @MainActor
    func testDeleteFileDeleteRemoveIndexCoreIndexedAndMissingEntriesUseRemoveFromIndex() async {
        let indexed = FileEntrySnapshot.deleteFixture(id: 231, name: "indexed.pdf", storageMode: "Indexed")
        var missing = FileEntrySnapshot.deleteFixture(id: 232, name: "missing.pdf", storageMode: "Copied")
        let external = FileEntrySnapshot.deleteFixture(
            id: 234,
            name: "external.pdf",
            storageMode: "Copied",
            origin: "External"
        )
        missing.availability = .missing
        let deleter = DeleteRecordingDeleter()
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [indexed, missing, external]),
            fileLister: NoopFileLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(indexed)),
            fileDeleter: deleter,
            errorMapper: StaticCoreErrorMapper(mapping: .deleteIo())
        )

        XCTAssertEqual(MainFileDeleteOperation.recommended(for: indexed), .removeFromIndex)
        XCTAssertEqual(MainFileDeleteOperation.recommended(for: missing), .removeFromIndex)
        XCTAssertEqual(MainFileDeleteOperation.recommended(for: external), .removeFromIndex)

        await model.selectFiles([indexed.id])
        model.beginDelete()
        let didDelete = await model.submitDelete(fileID: indexed.id, operation: .removeFromIndex)

        XCTAssertTrue(didDelete)
        await deleter.assertFileDeletionRequests([.removeIndex(repoPath: "/tmp/repo", fileID: indexed.id)])
        XCTAssertEqual(model.files, [missing, external])
        XCTAssertEqual(model.statusBanner, .removedFileFromIndex(fileID: indexed.id))
    }

    @MainActor
    func testDeleteFileDeleteRemoveIndexCoreFailureKeepsSheetOpenAndMapsCoreError() async {
        let file = FileEntrySnapshot.deleteFixture(id: 233, name: "locked.pdf", storageMode: "Copied")
        let mapping = CoreErrorMappingSnapshot.deletePermissionDenied()
        let mapper = StaticCoreErrorMapper(mapping: mapping)
        let deleter = DeleteRecordingDeleter(deleteResult: .failure(CoreError.PermissionDenied(path: file.path)))
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [file]),
            fileLister: NoopFileLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(file)),
            fileDeleter: deleter,
            errorMapper: mapper
        )

        await model.selectFiles([file.id])
        model.beginDelete()
        let didDelete = await model.submitDelete(fileID: file.id, operation: .moveToTrash)

        XCTAssertFalse(didDelete)
        XCTAssertEqual(model.files, [file])
        XCTAssertEqual(model.selectedFileDetail, file)
        XCTAssertEqual(model.pendingActionDestination, .delete(fileID: file.id))
        XCTAssertEqual(model.deleteState, .failed(fileID: file.id, operation: .moveToTrash, mapping))
        await mapper.assertMappedCoreErrors([CoreError.PermissionDenied(path: file.path)])
    }

    @MainActor
    func testDeleteFileDeleteRemoveIndexCoreDetailMissingBannerRoutesRemoveFromIndexToDeleteSheet() async {
        var missing = FileEntrySnapshot.deleteFixture(id: 235, name: "missing.pdf", storageMode: "Copied")
        missing.availability = .missing
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [missing]),
            fileLister: NoopFileLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .failure(CoreError.FileNotFound(path: missing.path))),
            errorMapper: StaticCoreErrorMapper(mapping: .detailMetaFileNotFound())
        )

        await model.selectFiles([missing.id])
        model.beginDelete(fileID: missing.id)

        XCTAssertEqual(model.selectedFileDetail, missing)
        XCTAssertEqual(model.detailErrorMapping?.kind, .fileNotFound)
        XCTAssertEqual(MainFileDeleteOperation.recommended(for: missing), .removeFromIndex)
        XCTAssertEqual(model.pendingActionDestination, .delete(fileID: missing.id))
        XCTAssertEqual(model.pendingActionDestination?.pageID, "delete-file")
    }

    func testDeleteFileDeleteRemoveIndexCoreFailurePrimaryActionUsesRetryCopy() {
        let fileID: Int64 = 236
        let state = MainFileDeleteState.failed(fileID: fileID, operation: .removeFromIndex, .deleteIo())

        XCTAssertEqual(
            state.primaryActionTitle(fileID: fileID, operation: .removeFromIndex),
            "Retry"
        )
        XCTAssertEqual(
            state.primaryActionTitle(fileID: 999, operation: .removeFromIndex),
            "Remove from Index"
        )
    }

    func testDeleteFileDeleteRemoveIndexCoreDefaultCoreBridgeRemovesIndexedEntryWithoutTouchingSource() async throws {
        let repoURL = try makeDeleteTemporaryDirectory(prefix: "repo")
        let sourceRoot = try makeDeleteTemporaryDirectory(prefix: "source")
        defer { removeTestTemporaryItems(repoURL, sourceRoot) }
        let sourceURL = sourceRoot.appendingPathComponent("external.pdf")
        try Data("external bytes".utf8).write(to: sourceURL)
        let sourceBefore = try Data(contentsOf: sourceURL)
        let bridge = CoreBridge()

        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let entry = try await bridge.importIndexedFile(
            repoPath: repoURL.path,
            sourceURL: sourceURL,
            overrideCategory: "docs",
            overrideFilename: "external.pdf"
        )
        try await bridge.removeIndexEntry(repoPath: repoURL.path, fileID: entry.id)
        let files = try await bridge.listFiles(repoPath: repoURL.path, filter: .currentCategory(nil))
        let changes = try await bridge.listChanges(repoPath: repoURL.path, filter: .detailLog(fileID: entry.id))

        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBefore)
        XCTAssertEqual(files, [])
        XCTAssertTrue(changes.contains { $0.action == "removed_from_index" })
    }

    func testDeleteFileDeleteRemoveIndexCoreDefaultCoreBridgeRejectsWrongOperationWithoutSideEffects() async throws {
        let repoURL = try makeDeleteTemporaryDirectory(prefix: "repo")
        let sourceRoot = try makeDeleteTemporaryDirectory(prefix: "source")
        defer { removeTestTemporaryItems(repoURL, sourceRoot) }
        let sourceURL = sourceRoot.appendingPathComponent("owned.pdf")
        try Data("owned bytes".utf8).write(to: sourceURL)
        let bridge = CoreBridge()

        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let entry = try await bridge.importCopiedFile(
            repoPath: repoURL.path,
            sourceURL: sourceURL,
            overrideCategory: "docs",
            overrideFilename: "owned.pdf",
            duplicateStrategy: .skip
        )

        do {
            try await bridge.removeIndexEntry(repoPath: repoURL.path, fileID: entry.id)
            XCTFail("remove_index_entry should reject repo-owned copied files")
        } catch CoreError.PermissionDenied(_) {
            XCTAssertTrue(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent(entry.path).path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
            let files = try await bridge.listFiles(repoPath: repoURL.path, filter: .currentCategory(nil))
            XCTAssertEqual(files.map(\.id), [entry.id])
        }
    }
}

extension FileEntrySnapshot {
    static func deleteFixture(
        id: Int64,
        name: String,
        storageMode: String,
        origin: String = "Imported"
    ) -> FileEntrySnapshot {
        FileEntrySnapshot.testFixture(
            id: id,
            path: "docs/contracts/\(name)",
            currentName: name,
            category: "docs"
        ) {
            $0.sizeBytes = 512
            $0.hashSha256 = "delete-\(id)"
            $0.storageMode = storageMode
            $0.origin = origin
        }
    }
}

private extension CoreErrorMappingSnapshot {
    static func deleteIo() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: .io,
            userMessage: "Delete failed.",
            severity: .high,
            suggestedAction: "Review file permissions and retry.",
            recoverability: .retryable,
            rawContext: "delete-file delete-remove-index delete_file"
        )
    }

    static func deletePermissionDenied() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: .permissionDenied,
            userMessage: "AreaMatrix cannot move this file to Trash.",
            severity: .high,
            suggestedAction: "Grant access or handle the file in Finder, then retry.",
            recoverability: .userActionRequired,
            rawContext: "delete-file delete-remove-index delete_file"
        )
    }
}

private func makeDeleteTemporaryDirectory(prefix: String) throws -> URL {
    try makeTestTemporaryDirectory(prefix: prefix, named: "AreaMatrixDeleteFile")
}
