import AreaMatrixCoreSDK
import CryptoKit
import Foundation

struct FilesImportBatchDeletePreviewItem {
    var fileID: Int64
    var willMoveToTrash: Bool
    var status: FilesImportBatchDeletePreviewStatus
    var reason: String?
}

enum FilesImportBatchDeletePreviewStatus {
    case willMoveToTrash
    case indexOnly
    case missing
    case skipped
    case blocked
}

struct FilesImportBatchDeletePreviewReport {
    var previewToken: String
    var trashAvailable: Bool
    var undoAvailable: Bool
    var canApply: Bool
    var applyBlockedReason: String?
    var items: [FilesImportBatchDeletePreviewItem]

    func blockedReason(for item: FilesImportBatchDeletePreviewItem?) -> String {
        if !trashAvailable {
            return "Replace requires system Trash."
        }
        if let applyBlockedReason, !applyBlockedReason.isEmpty {
            return applyBlockedReason
        }
        if let itemReason = item?.reason, !itemReason.isEmpty {
            return itemReason
        }
        return "Core delete preflight did not approve this replace."
    }
}

struct FilesImportBatchDeleteReport {
    var movedToTrashCount: Int64
    var failedCount: Int64
    var itemResults: [FilesImportBatchDeleteItemResult]
    var affectedFileIDs: [Int64]
    var undoToken: String?

    var failureSummary: String {
        itemResults.compactMap(\.error).first ?? "Core could not move the existing file to Trash."
    }
}

struct FilesImportBatchDeleteItemResult {
    var error: String?
}

struct FilesImportBatchDeleteFFIClient {
    func previewBatchDelete(repoPath: String, fileID: Int64) throws -> FilesImportBatchDeletePreviewReport {
        do {
            return FilesImportBatchDeleteCoreSDKMapping.preview(
                try AreaMatrixCoreSDK.previewBatchDelete(
                    repoPath: repoPath,
                    fileIds: [fileID],
                    deleteMode: .moveToTrash
                )
            )
        } catch {
            throw FilesImportCoreSDKMapping.error(error)
        }
    }

    func batchDeleteToTrash(repoPath: String, fileID: Int64, previewToken: String) throws
        -> FilesImportBatchDeleteReport {
        do {
            return FilesImportBatchDeleteCoreSDKMapping.report(
                try AreaMatrixCoreSDK.batchDeleteToTrash(
                    repoPath: repoPath,
                    fileIds: [fileID],
                    deleteMode: .moveToTrash,
                    previewToken: previewToken
                )
            )
        } catch {
            throw FilesImportCoreSDKMapping.error(error)
        }
    }
}

enum FilesImportBatchDeleteCoreSDKMapping {
    static func preview(
        _ value: AreaMatrixCoreSDK.BatchDeletePreviewReport
    ) -> FilesImportBatchDeletePreviewReport {
        FilesImportBatchDeletePreviewReport(
            previewToken: value.previewToken,
            trashAvailable: value.trashAvailable,
            undoAvailable: value.undoAvailable,
            canApply: value.canApply,
            applyBlockedReason: value.applyBlockedReason,
            items: value.items.map { item in
                FilesImportBatchDeletePreviewItem(
                    fileID: item.fileId,
                    willMoveToTrash: item.willMoveToTrash,
                    status: status(item.status),
                    reason: item.reason
                )
            }
        )
    }

    static func report(
        _ value: AreaMatrixCoreSDK.BatchDeleteReport
    ) -> FilesImportBatchDeleteReport {
        FilesImportBatchDeleteReport(
            movedToTrashCount: value.movedToTrashCount,
            failedCount: value.failedCount,
            itemResults: value.itemResults.map { FilesImportBatchDeleteItemResult(error: $0.error) },
            affectedFileIDs: value.affectedFileIds,
            undoToken: value.undoToken
        )
    }

    private static func status(
        _ value: AreaMatrixCoreSDK.BatchDeletePreviewStatus
    ) -> FilesImportBatchDeletePreviewStatus {
        switch value {
        case .willMoveToTrash:
            .willMoveToTrash
        case .indexOnly:
            .indexOnly
        case .missing:
            .missing
        case .skipped:
            .skipped
        case .blocked:
            .blocked
        }
    }
}

enum SHA256FileHasher {
    static func hash(url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1_048_576) ?? Data()
            if chunk.isEmpty {
                break
            }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
