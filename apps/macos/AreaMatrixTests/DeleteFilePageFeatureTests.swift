@testable import AreaMatrix
import XCTest

final class DeleteFilePageFeatureTests: XCTestCase {
    @MainActor
    func testS134C123MoveToTrashUsesCoreBridgeAndClearsSelection() async {
        let file = FileEntrySnapshot.deleteFixture(id: 230, name: "owned.pdf", storageMode: "Copied")
        let deleter = DeleteRecordingDeleter()
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [file]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(file)),
            fileDeleter: deleter,
            changeLogLister: DetailLogRecordingLister(results: [.success([])]),
            errorMapper: DetailMetaErrorMapper(mapping: .deleteIo())
        )

        await model.selectFiles([file.id])
        model.beginDelete()
        let didDelete = await model.submitDelete(fileID: file.id, operation: .moveToTrash)
        let requests = await deleter.recordedRequests()

        XCTAssertTrue(didDelete)
        XCTAssertEqual(requests, [.delete(repoPath: "/tmp/repo", fileID: file.id)])
        XCTAssertEqual(model.files, [])
        XCTAssertEqual(model.selection, .none)
        XCTAssertNil(model.selectedFileDetail)
        XCTAssertNil(model.pendingActionDestination)
        XCTAssertEqual(model.deleteState, .idle)
        XCTAssertEqual(model.statusBanner, .movedFileToTrash(fileID: file.id))
    }

    @MainActor
    func testS134C123IndexedAndMissingEntriesUseRemoveFromIndex() async {
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
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(indexed)),
            fileDeleter: deleter,
            errorMapper: DetailMetaErrorMapper(mapping: .deleteIo())
        )

        XCTAssertEqual(MainFileDeleteOperation.recommended(for: indexed), .removeFromIndex)
        XCTAssertEqual(MainFileDeleteOperation.recommended(for: missing), .removeFromIndex)
        XCTAssertEqual(MainFileDeleteOperation.recommended(for: external), .removeFromIndex)

        await model.selectFiles([indexed.id])
        model.beginDelete()
        let didDelete = await model.submitDelete(fileID: indexed.id, operation: .removeFromIndex)
        let requests = await deleter.recordedRequests()

        XCTAssertTrue(didDelete)
        XCTAssertEqual(requests, [.removeIndex(repoPath: "/tmp/repo", fileID: indexed.id)])
        XCTAssertEqual(model.files, [missing, external])
        XCTAssertEqual(model.statusBanner, .removedFileFromIndex(fileID: indexed.id))
    }

    @MainActor
    func testS134C123FailureKeepsSheetOpenAndMapsCoreError() async {
        let file = FileEntrySnapshot.deleteFixture(id: 233, name: "locked.pdf", storageMode: "Copied")
        let mapping = CoreErrorMappingSnapshot.deletePermissionDenied()
        let mapper = DetailMetaErrorMapper(mapping: mapping)
        let deleter = DeleteRecordingDeleter(deleteResult: .failure(CoreError.PermissionDenied(path: file.path)))
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [file]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(file)),
            fileDeleter: deleter,
            errorMapper: mapper
        )

        await model.selectFiles([file.id])
        model.beginDelete()
        let didDelete = await model.submitDelete(fileID: file.id, operation: .moveToTrash)
        let mappedErrors = await mapper.recordedErrors()

        XCTAssertFalse(didDelete)
        XCTAssertEqual(model.files, [file])
        XCTAssertEqual(model.selectedFileDetail, file)
        XCTAssertEqual(model.pendingActionDestination, .delete(fileID: file.id))
        XCTAssertEqual(model.deleteState, .failed(fileID: file.id, operation: .moveToTrash, mapping))
        XCTAssertEqual(mappedErrors, [CoreError.PermissionDenied(path: file.path)])
    }

    @MainActor
    func testS134C123DetailMissingBannerRoutesRemoveFromIndexToDeleteSheet() async {
        var missing = FileEntrySnapshot.deleteFixture(id: 235, name: "missing.pdf", storageMode: "Copied")
        missing.availability = .missing
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [missing]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .failure(CoreError.FileNotFound(path: missing.path))),
            errorMapper: DetailMetaErrorMapper(mapping: .detailMetaFileNotFound())
        )

        await model.selectFiles([missing.id])
        model.beginDelete(fileID: missing.id)

        XCTAssertEqual(model.selectedFileDetail, missing)
        XCTAssertEqual(model.detailErrorMapping?.kind, .fileNotFound)
        XCTAssertEqual(MainFileDeleteOperation.recommended(for: missing), .removeFromIndex)
        XCTAssertEqual(model.pendingActionDestination, .delete(fileID: missing.id))
        XCTAssertEqual(model.pendingActionDestination?.pageID, "S1-34")
    }

    func testS134C123FailurePrimaryActionUsesRetryCopy() {
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

    func testS134C123DefaultCoreBridgeRemovesIndexedEntryWithoutTouchingSource() async throws {
        let repoURL = try makeDeleteTemporaryDirectory(prefix: "repo")
        let sourceRoot = try makeDeleteTemporaryDirectory(prefix: "source")
        defer {
            try? FileManager.default.removeItem(at: repoURL)
            try? FileManager.default.removeItem(at: sourceRoot)
        }
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

    func testS134C123DefaultCoreBridgeRejectsWrongOperationWithoutSideEffects() async throws {
        let repoURL = try makeDeleteTemporaryDirectory(prefix: "repo")
        let sourceRoot = try makeDeleteTemporaryDirectory(prefix: "source")
        defer {
            try? FileManager.default.removeItem(at: repoURL)
            try? FileManager.default.removeItem(at: sourceRoot)
        }
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

private enum DeleteRequest: Equatable {
    case delete(repoPath: String, fileID: Int64)
    case removeIndex(repoPath: String, fileID: Int64)
}

private actor DeleteRecordingDeleter: CoreFileDeleting {
    private let deleteResult: Result<Void, Error>
    private let removeIndexResult: Result<Void, Error>
    private var requests: [DeleteRequest] = []

    init(
        deleteResult: Result<Void, Error> = .success(()),
        removeIndexResult: Result<Void, Error> = .success(())
    ) {
        self.deleteResult = deleteResult
        self.removeIndexResult = removeIndexResult
    }

    func deleteFile(repoPath: String, fileID: Int64) async throws {
        requests.append(.delete(repoPath: repoPath, fileID: fileID))
        try deleteResult.get()
    }

    func removeIndexEntry(repoPath: String, fileID: Int64) async throws {
        requests.append(.removeIndex(repoPath: repoPath, fileID: fileID))
        try removeIndexResult.get()
    }

    func recordedRequests() -> [DeleteRequest] {
        requests
    }
}

extension FileEntrySnapshot {
    static func deleteFixture(
        id: Int64,
        name: String,
        storageMode: String,
        origin: String = "Imported"
    ) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: "docs/contracts/\(name)",
            originalName: name,
            currentName: name,
            category: "docs",
            sizeBytes: 512,
            hashSha256: "delete-\(id)",
            storageMode: storageMode,
            origin: origin,
            sourcePath: nil,
            importedAt: 1_700_000_000,
            updatedAt: 1_700_000_100
        )
    }
}

private extension CoreErrorMappingSnapshot {
    static func deleteIo() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .io,
            userMessage: "Delete failed.",
            severity: .high,
            suggestedAction: "Review file permissions and retry.",
            recoverability: .retryable,
            rawContext: "S1-34 C1-23 delete_file"
        )
    }

    static func deletePermissionDenied() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .permissionDenied,
            userMessage: "AreaMatrix cannot move this file to Trash.",
            severity: .high,
            suggestedAction: "Grant access or handle the file in Finder, then retry.",
            recoverability: .userActionRequired,
            rawContext: "S1-34 C1-23 delete_file"
        )
    }
}

private func makeDeleteTemporaryDirectory(prefix: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixDeleteFile-\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
