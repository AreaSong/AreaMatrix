@testable import AreaMatrix
import Foundation
import XCTest

final class S213BatchDeleteVerifyTests: XCTestCase {
    // swiftlint:disable:next function_body_length
    func testS213MoveToTrashUsesRealCorePreviewApplyAndUndoToken() async throws {
        let context = try await makeS213IntegrationContext()
        defer { context.cleanUp() }

        let route = BatchDeleteRoute(
            source: .commandPalette,
            fileIDs: [context.repoOwned.id],
            selectedFiles: [context.repoOwned],
            selectedCount: 1,
            disabledReason: BatchDeleteEntryPolicy.disabledReason(
                selectedFiles: [context.repoOwned],
                isReadOnly: false,
                isLoading: false,
                writeLockedFileIDs: []
            )
        )
        XCTAssertNil(route.disabledReason)

        try await withS213TestTrash(homeURL: context.homeURL) {
            let preview = try await context.bridge.previewBatchDelete(
                repoPath: context.repoURL.path,
                fileIDs: route.fileIDs,
                deleteMode: .moveToTrash
            )
            XCTAssertTrue(preview.canApply)
            XCTAssertTrue(preview.trashAvailable)
            XCTAssertTrue(preview.undoAvailable)
            XCTAssertEqual(preview.willTrashCount, 1)
            XCTAssertEqual(preview.indexOnlyCount, 0)
            XCTAssertEqual(preview.blockedCount, 0)
            XCTAssertEqual(preview.items.map(\.status), [.willMoveToTrash])
            XCTAssertTrue(FileManager.default.fileExists(atPath: context.repoOwnedURL.path))

            let report = try await context.bridge.batchDeleteToTrash(
                repoPath: context.repoURL.path,
                fileIDs: preview.fileIDs,
                deleteMode: preview.deleteMode,
                previewToken: preview.previewToken
            )
            XCTAssertEqual(report.movedToTrashCount, 1)
            XCTAssertEqual(report.removedFromIndexCount, 0)
            XCTAssertEqual(report.failedCount, 0)
            XCTAssertEqual(report.affectedFileIDs, [context.repoOwned.id])
            XCTAssertEqual(report.itemResults.map(\.status), [.movedToTrash])
            let undoToken = try XCTUnwrap(report.undoToken)

            XCTAssertFalse(FileManager.default.fileExists(atPath: context.repoOwnedURL.path))
            XCTAssertEqual(
                try Data(contentsOf: context.trashURL.appendingPathComponent("batch-owned.pdf")),
                Data("repo owned bytes".utf8)
            )
            let visibleFiles = try await context.bridge.listFiles(
                repoPath: context.repoURL.path,
                filter: .currentCategory(nil)
            )
            XCTAssertFalse(visibleFiles.contains { $0.id == context.repoOwned.id })

            let undoState = await BatchDeleteUndoAction.stateAfterBatchApply(
                repoPath: context.repoURL.path,
                report: report,
                failure: nil,
                undoStore: context.bridge,
                errorMapper: context.bridge
            )
            guard case let .ready(action) = undoState else {
                return XCTFail("Expected real C2-09 apply to expose a C2-07 undo action")
            }
            XCTAssertEqual(action.actionID, undoToken)
            XCTAssertEqual(action.kind, "trash_delete")
            XCTAssertEqual(action.affectedCount, 1)
            XCTAssertTrue(action.canUndo)
        }
    }

    func testS213RemoveFromIndexUsesRealCoreWithoutTouchingExternalSource() async throws {
        let context = try await makeS213IntegrationContext()
        defer { context.cleanUp() }
        let externalBytes = try Data(contentsOf: context.indexOnlySourceURL)

        try await withS213TestTrash(homeURL: context.homeURL) {
            let wrongModePreview = try await context.bridge.previewBatchDelete(
                repoPath: context.repoURL.path,
                fileIDs: [context.indexOnly.id],
                deleteMode: .moveToTrash
            )
            XCTAssertFalse(wrongModePreview.canApply)
            XCTAssertEqual(wrongModePreview.willTrashCount, 0)
            XCTAssertEqual(wrongModePreview.skippedCount, 1)
            XCTAssertEqual(wrongModePreview.items.map(\.status), [.skipped])

            let preview = try await context.bridge.previewBatchDelete(
                repoPath: context.repoURL.path,
                fileIDs: [context.indexOnly.id],
                deleteMode: .removeFromIndex
            )
            XCTAssertTrue(preview.canApply)
            XCTAssertFalse(preview.undoAvailable)
            XCTAssertEqual(preview.willTrashCount, 0)
            XCTAssertEqual(preview.indexOnlyCount, 1)
            XCTAssertEqual(preview.items.map(\.status), [.indexOnly])

            let report = try await context.bridge.batchDeleteToTrash(
                repoPath: context.repoURL.path,
                fileIDs: preview.fileIDs,
                deleteMode: preview.deleteMode,
                previewToken: preview.previewToken
            )
            XCTAssertEqual(report.movedToTrashCount, 0)
            XCTAssertEqual(report.removedFromIndexCount, 1)
            XCTAssertEqual(report.failedCount, 0)
            XCTAssertNil(report.undoToken)
            XCTAssertEqual(report.itemResults.map(\.status), [.removedFromIndex])

            XCTAssertEqual(try Data(contentsOf: context.indexOnlySourceURL), externalBytes)
            XCTAssertFalse(FileManager.default
                .fileExists(atPath: context.trashURL.appendingPathComponent("indexed.pdf").path))
            let visibleFiles = try await context.bridge.listFiles(
                repoPath: context.repoURL.path,
                filter: .currentCategory(nil)
            )
            XCTAssertFalse(visibleFiles.contains { $0.id == context.indexOnly.id })
            let undoActions = try await context.bridge.listUndoActions(repoPath: context.repoURL.path)
            XCTAssertEqual(undoActions, [])
        }
    }

    func testS213ValidationUsesPreviewFileIDsForRetrySubset() {
        let preview = BatchDeletePreviewReportSnapshot.s213Fixture(fileIDs: [20])

        XCTAssertTrue(BatchDeleteValidation.canApply(BatchDeleteApplyGate(
            fileIDs: [10, 20],
            preview: preview,
            deleteMode: .moveToTrash,
            disabledReason: nil,
            undoConfirmationAccepted: false,
            isApplying: false
        )))
        XCTAssertFalse(BatchDeleteValidation.canApply(BatchDeleteApplyGate(
            fileIDs: [10],
            preview: preview,
            deleteMode: .moveToTrash,
            disabledReason: nil,
            undoConfirmationAccepted: false,
            isApplying: false
        )))
    }
}

private struct S213IntegrationContext {
    let repoURL: URL
    let sourceRootURL: URL
    let homeURL: URL
    let trashURL: URL
    let indexOnlySourceURL: URL
    let repoOwnedURL: URL
    let bridge: CoreBridge
    let repoOwned: FileEntrySnapshot
    let indexOnly: FileEntrySnapshot

    func cleanUp() {
        try? FileManager.default.removeItem(at: repoURL)
        try? FileManager.default.removeItem(at: sourceRootURL)
        try? FileManager.default.removeItem(at: homeURL)
    }
}

private func makeS213IntegrationContext() async throws -> S213IntegrationContext {
    let repoURL = try makeImportSingleFileTemporaryDirectory(prefix: "s213-repo")
    let sourceRootURL = try makeImportSingleFileTemporaryDirectory(prefix: "s213-source")
    let homeURL = try makeImportSingleFileTemporaryDirectory(prefix: "s213-home")
    let trashURL = homeURL.appendingPathComponent(".Trash", isDirectory: true)
    try FileManager.default.createDirectory(at: trashURL, withIntermediateDirectories: true)

    let repoOwnedSourceURL = sourceRootURL.appendingPathComponent("batch-owned.pdf")
    let indexOnlySourceURL = sourceRootURL.appendingPathComponent("indexed.pdf")
    try Data("repo owned bytes".utf8).write(to: repoOwnedSourceURL)
    try Data("indexed bytes".utf8).write(to: indexOnlySourceURL)

    let bridge = CoreBridge()
    try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
    let repoOwned = try await bridge.importCopiedFile(
        repoPath: repoURL.path,
        sourceURL: repoOwnedSourceURL,
        overrideCategory: "docs",
        overrideFilename: "batch-owned.pdf",
        duplicateStrategy: .skip
    )
    let indexOnly = try await bridge.importIndexedFile(
        repoPath: repoURL.path,
        sourceURL: indexOnlySourceURL,
        overrideCategory: "docs",
        overrideFilename: "indexed.pdf",
        duplicateStrategy: .skip
    )

    return S213IntegrationContext(
        repoURL: repoURL,
        sourceRootURL: sourceRootURL,
        homeURL: homeURL,
        trashURL: trashURL,
        indexOnlySourceURL: indexOnlySourceURL,
        repoOwnedURL: repoURL.appendingPathComponent(repoOwned.path),
        bridge: bridge,
        repoOwned: repoOwned,
        indexOnly: indexOnly
    )
}

private func withS213TestTrash<T>(
    homeURL: URL,
    operation: () async throws -> T
) async throws -> T {
    await s213TrashEnvironmentGate.acquire()
    let environment = ProcessInfo.processInfo.environment
    let previousHome = environment["HOME"]
    let previousForce = environment["AREAMATRIX_TEST_FORCE_USER_TRASH"]
    setenv("HOME", homeURL.path, 1)
    setenv("AREAMATRIX_TEST_FORCE_USER_TRASH", "1", 1)
    do {
        let result = try await operation()
        restoreS213Env(name: "HOME", value: previousHome)
        restoreS213Env(name: "AREAMATRIX_TEST_FORCE_USER_TRASH", value: previousForce)
        await s213TrashEnvironmentGate.release()
        return result
    } catch {
        restoreS213Env(name: "HOME", value: previousHome)
        restoreS213Env(name: "AREAMATRIX_TEST_FORCE_USER_TRASH", value: previousForce)
        await s213TrashEnvironmentGate.release()
        throw error
    }
}

private actor S213TrashEnvironmentGate {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !isLocked {
            isLocked = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            isLocked = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

private let s213TrashEnvironmentGate = S213TrashEnvironmentGate()

private func restoreS213Env(name: String, value: String?) {
    if let value {
        setenv(name, value, 1)
    } else {
        unsetenv(name)
    }
}

private extension BatchDeletePreviewReportSnapshot {
    static func s213Fixture(fileIDs: [Int64]) -> BatchDeletePreviewReportSnapshot {
        BatchDeletePreviewReportSnapshot(
            requestedFileCount: Int64(fileIDs.count),
            deleteMode: .moveToTrash,
            previewToken: "preview:batch-delete:test",
            trashAvailable: true,
            undoAvailable: true,
            willTrashCount: Int64(fileIDs.count),
            indexOnlyCount: 0,
            missingCount: 0,
            skippedCount: 0,
            blockedCount: 0,
            items: fileIDs.map { id in
                BatchDeletePreviewItemSnapshot(
                    fileID: id,
                    currentPath: "docs/\(id).pdf",
                    currentName: "\(id).pdf",
                    storageMode: "Copied",
                    deleteMode: .moveToTrash,
                    willMoveToTrash: true,
                    willRemoveIndex: false,
                    status: .willMoveToTrash,
                    reason: nil
                )
            },
            canApply: true,
            applyBlockedReason: nil
        )
    }
}
