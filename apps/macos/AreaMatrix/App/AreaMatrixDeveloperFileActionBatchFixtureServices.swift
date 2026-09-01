import AreaMatrixFeatureOperation
import Foundation

#if DEBUG
extension DeveloperFileActionCoreFixture: CoreBatchDeleting,
    CoreBatchRenaming,
    CoreBatchCategoryChanging,
    CoreClassifierImpactPreviewing {
    func previewBatchDelete(
        repoPath _: String,
        fileIDs: [Int64],
        deleteMode: BatchDeleteModeSnapshot
    ) async throws -> BatchDeletePreviewReportSnapshot {
        makeBatchDeletePreview(fileIDs: fileIDs, deleteMode: deleteMode)
    }

    func batchDeleteToTrash(
        repoPath _: String,
        fileIDs: [Int64],
        deleteMode: BatchDeleteModeSnapshot,
        previewToken _: String
    ) async throws -> BatchDeleteReportSnapshot {
        let items = fileIDs.map { fileID -> BatchDeleteItemResultSnapshot in
            let file = DeveloperFileActionScenarioFixture.file(id: fileID)
            let removesIndex = deleteMode == .removeFromIndex || file.storageMode == "Indexed"
            return BatchDeleteItemResultSnapshot(
                fileID: fileID,
                finalPath: removesIndex ? nil : file.path,
                status: removesIndex ? .removedFromIndex : .movedToTrash,
                error: nil
            )
        }
        recordUndo(
            kind: "trash_delete",
            summary: "Processed \(fileIDs.count) selected files.",
            fileIDs: fileIDs,
            token: "developer-undo-batch-delete"
        )
        return BatchDeleteReportSnapshot(
            requestedFileCount: Int64(fileIDs.count),
            deleteMode: deleteMode,
            movedToTrashCount: Int64(items.filter { $0.status == .movedToTrash }.count),
            removedFromIndexCount: Int64(items.filter { $0.status == .removedFromIndex }.count),
            skippedCount: 0,
            failedCount: 0,
            itemResults: items,
            affectedFileIDs: fileIDs,
            undoToken: "developer-undo-batch-delete"
        )
    }

    func previewBatchRename(
        repoPath _: String,
        fileIDs: [Int64],
        rule: BatchRenameRuleSnapshot
    ) async throws -> BatchRenamePreviewReportSnapshot {
        makeBatchRenamePreview(fileIDs: fileIDs, rule: rule)
    }

    func batchRename(
        repoPath _: String,
        fileIDs: [Int64],
        rule: BatchRenameRuleSnapshot,
        previewToken _: String
    ) async throws -> BatchRenameReportSnapshot {
        let preview = makeBatchRenamePreview(fileIDs: fileIDs, rule: rule)
        let changed = preview.items.filter { $0.status == .ok }
        let updatedFiles = changed.map { item -> FileEntrySnapshot in
            var file = DeveloperFileActionScenarioFixture.file(id: item.fileID)
            file.currentName = item.newName ?? file.currentName
            file.path = item.targetPath ?? file.path
            return file
        }
        recordUndo(
            kind: "rename_files",
            summary: "Renamed \(changed.count) files.",
            fileIDs: changed.map(\.fileID),
            token: "developer-undo-batch-rename"
        )
        return BatchRenameReportSnapshot(
            requestedFileCount: Int64(fileIDs.count),
            renamedCount: Int64(changed.count),
            displayNameUpdatedCount: 0,
            unchangedCount: Int64(preview.items.filter { $0.status == .unchanged }.count),
            skippedCount: 0,
            failedCount: 0,
            itemResults: preview.items.map(renameResult),
            updatedFiles: updatedFiles,
            undoToken: changed.isEmpty ? nil : "developer-undo-batch-rename"
        )
    }

    func previewBatchMoveToCategory(
        repoPath _: String,
        fileIDs: [Int64],
        targetCategory: String,
        moveRepoOwnedFiles: Bool
    ) async throws -> BatchCategoryPreviewReportSnapshot {
        makeBatchCategoryPreview(
            fileIDs: fileIDs,
            targetCategory: targetCategory,
            moveRepoOwnedFiles: moveRepoOwnedFiles
        )
    }

    func batchMoveToCategory(
        repoPath _: String,
        fileIDs: [Int64],
        targetCategory: String,
        moveRepoOwnedFiles: Bool,
        previewToken _: String
    ) async throws -> BatchCategoryChangeReportSnapshot {
        let preview = makeBatchCategoryPreview(
            fileIDs: fileIDs,
            targetCategory: targetCategory,
            moveRepoOwnedFiles: moveRepoOwnedFiles
        )
        let results = preview.items.map(categoryResult)
        let updatedFiles = results.compactMap { result -> FileEntrySnapshot? in
            guard result.status == .moved || result.status == .metadataUpdated else { return nil }
            var file = DeveloperFileActionScenarioFixture.file(id: result.fileID)
            file.category = targetCategory
            file.path = result.finalPath ?? file.path
            return file
        }
        recordUndo(
            kind: "batch_move_to_category",
            summary: "Changed category for \(updatedFiles.count) files.",
            fileIDs: updatedFiles.map(\.id),
            token: "developer-undo-batch-category"
        )
        return BatchCategoryChangeReportSnapshot(
            requestedFileCount: Int64(fileIDs.count),
            targetCategory: targetCategory,
            movedCount: Int64(results.filter { $0.status == .moved }.count),
            metadataOnlyCount: Int64(results.filter { $0.status == .metadataUpdated }.count),
            unchangedCount: Int64(results.filter { $0.status == .unchanged }.count),
            skippedCount: 0,
            failedCount: 0,
            itemResults: results,
            updatedFiles: updatedFiles,
            undoToken: updatedFiles.isEmpty ? nil : "developer-undo-batch-category"
        )
    }

    func previewClassifierRuleImpact(
        repoPath _: String,
        request: ClassifierImpactPreviewRequestSnapshot
    ) async throws -> RuleImpactReportSnapshot {
        let samples = makeRuleImpactSamples(request: request)
        return RuleImpactReportSnapshot(
            request: request,
            affectedFileCount: Int64(samples.count),
            willUpdateCount: Int64(samples.filter { $0.status == .willUpdate }.count),
            alreadyCorrectCount: Int64(samples.filter { $0.status == .alreadyCorrect }.count),
            needsReviewCount: Int64(samples.filter { $0.status == .indexOnly }.count),
            conflictCount: 0,
            sampleLimit: 50,
            samples: samples,
            conflicts: [],
            needsReview: true,
            warningRequired: true,
            warning: DeveloperFileActionScenarioFixture.technicalDetail(
                "Index-only files will update metadata without moving source files."
            ),
            canApply: false,
            applyBlockedReason: DeveloperFileActionScenarioFixture.technicalDetail(
                "This surface previews impact; saving and applying remain separate confirmed actions."
            )
        )
    }

    private func makeBatchDeletePreview(
        fileIDs: [Int64],
        deleteMode: BatchDeleteModeSnapshot
    ) -> BatchDeletePreviewReportSnapshot {
        let items = fileIDs.map { deletePreviewItem(fileID: $0, mode: deleteMode) }
        return BatchDeletePreviewReportSnapshot(
            requestedFileCount: Int64(fileIDs.count),
            deleteMode: deleteMode,
            previewToken: "developer-delete-\(deleteMode.rawValue)",
            trashAvailable: true,
            undoAvailable: true,
            willTrashCount: Int64(items.filter(\.willMoveToTrash).count),
            indexOnlyCount: Int64(items.filter { $0.status == .indexOnly }.count),
            missingCount: 0,
            skippedCount: 0,
            blockedCount: 0,
            items: items,
            canApply: !items.isEmpty,
            applyBlockedReason: nil
        )
    }

    private func deletePreviewItem(
        fileID: Int64,
        mode: BatchDeleteModeSnapshot
    ) -> BatchDeletePreviewItemSnapshot {
        let file = DeveloperFileActionScenarioFixture.file(id: fileID)
        let removesIndex = mode == .removeFromIndex || file.storageMode == "Indexed"
        return BatchDeletePreviewItemSnapshot(
            fileID: fileID,
            currentPath: file.path,
            currentName: file.currentName,
            storageMode: file.storageMode,
            deleteMode: mode,
            willMoveToTrash: !removesIndex,
            willRemoveIndex: removesIndex,
            status: removesIndex ? .indexOnly : .willMoveToTrash,
            reason: removesIndex ? DeveloperFileActionScenarioFixture.technicalDetail(
                "The external source file remains untouched."
            ) : nil
        )
    }

    private func makeBatchRenamePreview(
        fileIDs: [Int64],
        rule: BatchRenameRuleSnapshot
    ) -> BatchRenamePreviewReportSnapshot {
        let items = fileIDs.enumerated().map { index, fileID in
            renamePreviewItem(fileID: fileID, rule: rule, index: index)
        }
        let changedCount = items.filter { $0.status == .ok }.count
        return BatchRenamePreviewReportSnapshot(
            requestedFileCount: Int64(fileIDs.count),
            rule: rule,
            previewToken: "developer-rename-\(fileIDs.map(String.init).joined(separator: "-"))",
            willRenameCount: Int64(changedCount),
            displayOnlyCount: 0,
            unchangedCount: Int64(items.count - changedCount),
            blockedCount: 0,
            conflictCount: 0,
            items: items,
            canApply: changedCount > 0,
            applyBlockedReason: changedCount == 0
                ? DeveloperFileActionScenarioFixture.technicalDetail("Choose a rule that changes a filename.")
                : nil
        )
    }

    private func renamePreviewItem(
        fileID: Int64,
        rule: BatchRenameRuleSnapshot,
        index: Int
    ) -> BatchRenamePreviewItemSnapshot {
        let file = DeveloperFileActionScenarioFixture.file(id: fileID)
        let newName = renamedName(file.currentName, rule: rule, index: index)
        let changed = newName != file.currentName
        return BatchRenamePreviewItemSnapshot(
            fileID: fileID,
            currentPath: file.path,
            originalName: file.currentName,
            newName: newName,
            targetPath: DeveloperFileActionScenarioFixture.filesystemPath("\(file.category)/\(newName)"),
            status: changed ? .ok : .unchanged,
            reason: changed ? nil : DeveloperFileActionScenarioFixture.technicalDetail("No filename change.")
        )
    }

    private func renamedName(
        _ currentName: String,
        rule: BatchRenameRuleSnapshot,
        index: Int
    ) -> String {
        switch rule.mode {
        case .prefix:
            guard let prefix = rule.prefix, !prefix.isEmpty else { return currentName }
            return DeveloperFileActionScenarioFixture.userContent("\(prefix)\(currentName)")
        case .datePrefix:
            return DeveloperFileActionScenarioFixture.userContent("2026-07-29\(rule.separator ?? "_")\(currentName)")
        case .keepBaseSequence:
            return sequencedName(currentName, index: index, rule: rule)
        case .replaceText:
            guard let find = rule.find, !find.isEmpty else { return currentName }
            let options: String.CompareOptions = rule.caseSensitive ? [] : [.caseInsensitive]
            return DeveloperFileActionScenarioFixture.userContent(
                currentName.replacingOccurrences(of: find, with: rule.replacement ?? "", options: options)
            )
        }
    }

    private func sequencedName(
        _ currentName: String,
        index: Int,
        rule: BatchRenameRuleSnapshot
    ) -> String {
        let source = currentName as NSString
        let number = Int(rule.startNumber ?? 1) + index
        let padding = Int(rule.padding ?? 2)
        let sequence = String(format: "%0*d", padding, number)
        let separator = rule.separator ?? "_"
        let suffix = source.pathExtension.isEmpty ? "" : ".\(source.pathExtension)"
        return DeveloperFileActionScenarioFixture.userContent(
            "\(source.deletingPathExtension)\(separator)\(sequence)\(suffix)"
        )
    }

    private func renameResult(_ item: BatchRenamePreviewItemSnapshot) -> BatchRenameItemResultSnapshot {
        BatchRenameItemResultSnapshot(
            fileID: item.fileID,
            originalName: item.originalName,
            finalName: item.newName,
            finalPath: item.targetPath,
            status: item.status == .ok ? .renamed : .unchanged,
            error: nil
        )
    }

    private func makeBatchCategoryPreview(
        fileIDs: [Int64],
        targetCategory: String,
        moveRepoOwnedFiles: Bool
    ) -> BatchCategoryPreviewReportSnapshot {
        let items = fileIDs.map {
            categoryPreviewItem(fileID: $0, targetCategory: targetCategory, moveFiles: moveRepoOwnedFiles)
        }
        return BatchCategoryPreviewReportSnapshot(
            requestedFileCount: Int64(fileIDs.count),
            targetCategory: targetCategory,
            moveRepoOwnedFiles: moveRepoOwnedFiles,
            previewToken: "developer-category-\(targetCategory)",
            categoryDistribution: categoryDistribution(fileIDs: fileIDs),
            willMoveCount: Int64(items.filter { $0.status == .willMove }.count),
            metadataOnlyCount: Int64(items.filter { $0.status == .metadataOnly }.count),
            unchangedCount: Int64(items.filter { $0.status == .unchanged }.count),
            skippedCount: 0,
            blockedCount: 0,
            items: items,
            canApply: items.contains { $0.status == .willMove || $0.status == .metadataOnly },
            applyBlockedReason: nil
        )
    }

    private func categoryPreviewItem(
        fileID: Int64,
        targetCategory: String,
        moveFiles: Bool
    ) -> BatchCategoryPreviewItemSnapshot {
        let file = DeveloperFileActionScenarioFixture.file(id: fileID)
        let unchanged = file.category == targetCategory
        let willMove = !unchanged && moveFiles && file.storageMode != "Indexed"
        let status: BatchCategoryPreviewStatusSnapshot = unchanged ? .unchanged : (willMove ? .willMove : .metadataOnly)
        return BatchCategoryPreviewItemSnapshot(
            fileID: fileID,
            fromCategory: file.category,
            toCategory: targetCategory,
            currentPath: file.path,
            targetPath: DeveloperFileActionScenarioFixture.filesystemPath("\(targetCategory)/\(file.currentName)"),
            targetName: file.currentName,
            storageMode: file.storageMode,
            indexOnly: file.storageMode == "Indexed",
            willMoveFile: willMove,
            status: status,
            reason: file.storageMode == "Indexed"
                ? DeveloperFileActionScenarioFixture.technicalDetail("Index-only source files remain in place.")
                : nil
        )
    }

    private func categoryDistribution(fileIDs: [Int64]) -> [CategoryDistributionItemSnapshot] {
        let counts = Dictionary(grouping: fileIDs.map { DeveloperFileActionScenarioFixture.file(id: $0).category }) {
            $0
        }.mapValues { Int64($0.count) }
        return counts.keys.sorted().map { CategoryDistributionItemSnapshot(category: $0, count: counts[$0] ?? 0) }
    }

    private func categoryResult(_ item: BatchCategoryPreviewItemSnapshot) -> BatchCategoryChangeItemResultSnapshot {
        let status: BatchCategoryResultStatusSnapshot = switch item.status {
        case .willMove: .moved
        case .metadataOnly: .metadataUpdated
        case .unchanged: .unchanged
        case .skipped, .blocked: .skipped
        }
        return BatchCategoryChangeItemResultSnapshot(
            fileID: item.fileID,
            fromCategory: item.fromCategory,
            toCategory: item.toCategory,
            finalPath: item.targetPath,
            status: status,
            error: nil
        )
    }

    private func makeRuleImpactSamples(
        request: ClassifierImpactPreviewRequestSnapshot
    ) -> [RuleImpactSampleSnapshot] {
        DeveloperFileActionScenarioFixture.selectedFiles.enumerated().map { index, file in
            let status: RuleImpactStatusSnapshot = switch index {
            case 0: .willUpdate
            case 1: .alreadyCorrect
            default: .indexOnly
            }
            return RuleImpactSampleSnapshot(
                fileID: file.id,
                path: file.path,
                currentCategory: file.category,
                newCategory: request.rule.targetCategory,
                matchReasons: [.keyword, .extension],
                status: status,
                reason: status == .indexOnly
                    ? DeveloperFileActionScenarioFixture.technicalDetail("Metadata changes only.")
                    : nil
            )
        }
    }
}
#endif
