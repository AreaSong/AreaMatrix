import Foundation

struct FilesImportReplaceCoreFFIClient {
    func prepareReplace(request: FilesImportReplacePlanRequest) throws -> FilesImportReplacePlan {
        let existing = try findExistingFile(repoPath: request.repoPath, existingPath: request.existingPath)
        guard existing.isRepoOwnedAvailable else {
            return blockedPlan(request: request, file: existing, reason: "Only available copied or moved files can be replaced.")
        }

        let preview = try FilesImportBatchDeleteFFIClient().previewBatchDelete(
            repoPath: request.repoPath,
            fileID: existing.id
        )
        let newHash = try SHA256FileHasher.hash(url: request.sourceURL)
        return plan(request: request, file: existing, preview: preview, newHash: newHash)
    }

    func replaceSelectedFile(request: FilesImportReplaceRequest) throws -> FilesImportReplaceExecutionReport {
        guard request.plan.canReplace else {
            throw FilesImportError.replaceUnavailable(request.plan.blockedReason ?? "Replace is not available.")
        }

        let deleteReport = try FilesImportBatchDeleteFFIClient().batchDeleteToTrash(
            repoPath: request.repoPath,
            fileID: request.plan.affectedFileID,
            previewToken: request.plan.previewToken
        )
        guard deleteReport.movedToTrashCount == 1, deleteReport.failedCount == 0 else {
            throw FilesImportError.replaceUnavailable(deleteReport.failureSummary)
        }

        do {
            let imported = try FilesImportCoreFFIClient().importSelectedFile(request: FilesImportCoreRequest(
                repoPath: request.repoPath,
                sourceURL: request.sourceURL,
                filename: request.filename,
                category: request.category,
                duplicateStrategy: .skip
            ))
            return executionReport(plan: request.plan, imported: imported, deleteReport: deleteReport)
        } catch {
            throw FilesImportError.replaceUnavailable(request.plan.recoveryNote)
        }
    }

    private func findExistingFile(repoPath: String, existingPath: String) throws -> MobileLibraryFile {
        var offset: Int64 = 0
        let pageSize: Int64 = 200
        while true {
            let page = try MobileLibraryCoreFFIClient().listFiles(
                repoPath: repoPath,
                filter: .page(category: nil, limit: pageSize, offset: offset)
            )
            if let matched = page.first(where: { $0.matchesConflictPath(existingPath) }) {
                return matched
            }
            guard Int64(page.count) == pageSize else { break }
            offset += pageSize
        }
        throw FilesImportError.replaceUnavailable("Existing repository file could not be resolved from Core metadata.")
    }

    private func blockedPlan(
        request: FilesImportReplacePlanRequest,
        file: MobileLibraryFile,
        reason: String
    ) -> FilesImportReplacePlan {
        FilesImportReplacePlan(
            confirmationID: "blocked-\(file.id)",
            oldPath: file.path,
            newPath: request.targetRelativePath,
            oldHashSHA256: file.hashSha256,
            newHashSHA256: nil,
            affectedFileID: file.id,
            backupTarget: "Unavailable",
            databaseUpdate: "No database update will be applied.",
            changeLogAction: "none",
            recoveryNote: reason,
            trashAvailable: false,
            undoAvailable: false,
            canReplace: false,
            blockedReason: reason,
            previewToken: ""
        )
    }

    private func plan(
        request: FilesImportReplacePlanRequest,
        file: MobileLibraryFile,
        preview: FilesImportBatchDeletePreviewReport,
        newHash: String
    ) -> FilesImportReplacePlan {
        let item = preview.items.first { $0.fileID == file.id }
        let canReplace = preview.canApply && preview.trashAvailable && item?.willMoveToTrash == true
        return FilesImportReplacePlan(
            confirmationID: preview.previewToken,
            oldPath: file.path,
            newPath: request.targetRelativePath,
            oldHashSHA256: file.hashSha256,
            newHashSHA256: newHash,
            affectedFileID: file.id,
            backupTarget: "System Trash through Core batch_delete_to_trash.",
            databaseUpdate: "Soft-delete record \(file.id), then import \(request.targetRelativePath).",
            changeLogAction: "deleted + imported",
            recoveryNote: "If import fails after Trash, restore \(file.path) with the Core undo token or system Trash.",
            trashAvailable: preview.trashAvailable,
            undoAvailable: preview.undoAvailable,
            canReplace: canReplace,
            blockedReason: canReplace ? nil : preview.blockedReason(for: item),
            previewToken: preview.previewToken
        )
    }

    private func executionReport(
        plan: FilesImportReplacePlan,
        imported: MobileLibraryFile,
        deleteReport: FilesImportBatchDeleteReport
    ) -> FilesImportReplaceExecutionReport {
        FilesImportReplaceExecutionReport(
            importedFile: imported,
            oldFileID: plan.affectedFileID,
            oldPath: plan.oldPath,
            newPath: imported.path,
            oldHashSHA256: plan.oldHashSHA256,
            newHashSHA256: imported.hashSha256,
            backupTarget: plan.backupTarget,
            databaseUpdate: plan.databaseUpdate,
            changeLogAction: "deleted + imported",
            recoveryNote: plan.recoveryNote,
            undoToken: deleteReport.undoToken,
            affectedFileIDs: deleteReport.affectedFileIDs + [imported.id]
        )
    }
}

private extension MobileLibraryFile {
    var isRepoOwnedAvailable: Bool {
        (storageMode == "Copied" || storageMode == "Moved") && availability == .available
    }

    func matchesConflictPath(_ existingPath: String) -> Bool {
        path == existingPath || currentName == URL(fileURLWithPath: existingPath).lastPathComponent
    }
}
