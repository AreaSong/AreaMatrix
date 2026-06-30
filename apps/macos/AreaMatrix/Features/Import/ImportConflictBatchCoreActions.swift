import Foundation

enum ImportConflictBatchAction {
    static func preview(
        repoPath: String,
        request: ImportConflictBatchPreviewRequestSnapshot,
        batcher: any CoreImportConflictBatching,
        errorMapper: any CoreErrorMapping,
        previous: ImportConflictBatchPreviewReportSnapshot? = nil
    ) async -> ImportConflictBatchPreviewState {
        do {
            let report = try await batcher.previewImportConflictBatch(repoPath: repoPath, request: request)
            return .loaded(report)
        } catch {
            return await .failed(errorMapper.mapError(error), previous: previous)
        }
    }

    static func apply(
        repoPath: String,
        request: ImportConflictBatchApplyRequestSnapshot,
        preview: ImportConflictBatchPreviewReportSnapshot,
        batcher: any CoreImportConflictBatching,
        errorMapper: any CoreErrorMapping
    ) async -> ImportConflictBatchApplyResult {
        guard ImportConflictBatchValidation.canApply(
            preview: preview,
            request: request,
            isApplying: false
        ) else {
            let failure = CoreError.Conflict(path: preview.applyBlockedReason ?? "Import conflict batch")
            return await ImportConflictBatchApplyResult(
                report: nil,
                failure: errorMapper.mapError(failure)
            )
        }
        do {
            let report = try await batcher.applyImportConflictBatch(
                repoPath: repoPath,
                request: request,
                previewToken: preview.previewToken
            )
            return ImportConflictBatchApplyResult(report: report, failure: nil)
        } catch {
            return await ImportConflictBatchApplyResult(
                report: nil,
                failure: errorMapper.mapError(error)
            )
        }
    }
}

enum ImportConflictBatchValidation {
    static func actionableIncludedCount(preview: ImportConflictBatchPreviewReportSnapshot) -> Int64 {
        Int64(preview.items.filter(\.isActionablePreviewItem).count)
    }

    static func canApply(
        preview: ImportConflictBatchPreviewReportSnapshot?,
        request: ImportConflictBatchApplyRequestSnapshot,
        isApplying: Bool
    ) -> Bool {
        guard !isApplying,
              let preview,
              preview.canApply,
              !preview.previewToken.isEmpty, preview.importSessionID == request.importSessionID,
              actionableIncludedCount(preview: preview) > 0 else { return false }
        if preview.replaceConfirmationRequired, !request.replaceConfirmed { return false }
        return selectedStrategiesMatch(preview: preview, request: request)
    }

    static func canAskPerItem(preview: ImportConflictBatchPreviewReportSnapshot?, isApplying: Bool) -> Bool {
        guard !isApplying, let preview else { return false }
        return actionableIncludedCount(preview: preview) > 0
    }

    static func confirmationTitle(for preview: ImportConflictBatchPreviewReportSnapshot?) -> String {
        let count = preview?.replaceCount ?? 0
        return "Replace \(count) existing \(count == 1 ? "file" : "files")?"
    }

    private static func selectedStrategiesMatch(
        preview: ImportConflictBatchPreviewReportSnapshot,
        request: ImportConflictBatchApplyRequestSnapshot
    ) -> Bool {
        preview.applyToAllSimilarConflicts == request.applyToAllSimilarConflicts
            && preview.items.allSatisfy { item in
                guard item.isActionablePreviewItem else { return true }
                switch item.conflictType {
                case .duplicateHash:
                    return item.selectedStrategy == request.duplicateStrategy
                case .sameNameDifferentContent:
                    return item.selectedStrategy == request.sameNameStrategy
                }
            }
    }
}
