@testable import AreaMatrix

extension ClassifyResultSnapshot {
    static func importBatchPrediction(
        category: String,
        suggestedName: String,
        confidence: Float = 0.9
    ) -> ClassifyResultSnapshot {
        .testFixture(
            category: category,
            suggestedName: suggestedName,
            reason: .keyword,
            confidence: confidence
        )
    }
}

extension ImportConflictBatchPreviewReportSnapshot {
    static func importConflictBatchPreview(canApply: Bool) -> ImportConflictBatchPreviewReportSnapshot {
        let status: ImportConflictBatchPreviewStatusSnapshot = canApply ? .needsConfirmation : .blocked
        return ImportConflictBatchPreviewReportSnapshot(
            importSessionID: "session-221",
            previewToken: canApply ? "token-replace" : "token-blocked",
            applyToAllSimilarConflicts: true,
            requestedConflictCount: 1,
            duplicateConflictCount: 1,
            sameNameConflictCount: 0,
            includedCount: 1,
            pendingCount: 0,
            blockedCount: canApply ? 0 : 1,
            replaceCount: 1,
            skipCount: 0,
            keepBothCount: 0,
            askPerItemCount: 0,
            trashAvailable: canApply,
            undoAvailable: canApply,
            canApply: canApply,
            applyBlockedReason: canApply ? nil : "Blocked: Trash unavailable",
            replaceConfirmationRequired: true,
            replaceConfirmationSummary: "Replace 1 existing file?",
            items: [.importConflictBatchItem(
                conflictID: canApply ? "dup-1" : "dup-blocked",
                strategy: .replace,
                status: status
            )]
        )
    }

    func withImportConflictBatchRequest(_ request: ImportConflictBatchPreviewRequestSnapshot)
        -> ImportConflictBatchPreviewReportSnapshot {
        var copy = self
        copy.importSessionID = request.importSessionID
        copy.applyToAllSimilarConflicts = request.applyToAllSimilarConflicts
        copy.requestedConflictCount = Int64(request.conflictIDs.count)
        copy.includedCount = Int64(request.conflictIDs.count)
        copy.items = request.conflictIDs.map { conflictID in
            let source = items.first { $0.conflictID == conflictID }
            let type = source?.conflictType ?? .duplicateHash
            let strategy = type == .duplicateHash ? request.duplicateStrategy : request.sameNameStrategy
            let status = copy.previewStatusForImportConflictBatchRequest(strategy: strategy)
            return .importConflictBatchItem(conflictID: conflictID, strategy: strategy, status: status)
                .withConflictType(type)
        }
        return copy
    }

    private func previewStatusForImportConflictBatchRequest(
        strategy: ImportConflictBatchStrategySnapshot
    ) -> ImportConflictBatchPreviewStatusSnapshot {
        guard canApply else { return .blocked }
        return strategy == .replace ? .needsConfirmation : .ready
    }
}

extension ImportConflictBatchPreviewItemSnapshot {
    static func importConflictBatchItem(
        conflictID: String,
        strategy: ImportConflictBatchStrategySnapshot,
        status: ImportConflictBatchPreviewStatusSnapshot
    ) -> ImportConflictBatchPreviewItemSnapshot {
        ImportConflictBatchPreviewItemSnapshot(
            conflictID: conflictID,
            conflictType: .duplicateHash,
            existingFileID: 42,
            existingPath: "finance/existing-invoice.pdf",
            incomingPath: "/tmp/Invoice_2026Q1.pdf",
            targetPath: "finance/Invoice_2026Q1.pdf",
            selectedStrategy: strategy,
            status: status,
            willReplace: strategy == .replace,
            willKeepBoth: strategy == .keepBoth,
            willSkip: strategy == .skip,
            willAskPerItem: strategy == .askPerItem,
            indexOnly: false,
            riskSummary: "Existing file remains unless Replace is confirmed.",
            reason: status == .blocked ? "Trash unavailable" : nil
        )
    }
}

extension ImportConflictBatchApplyReportSnapshot {
    static func importConflictBatchIntegrationReport(
        for request: ImportConflictBatchApplyRequestSnapshot
    ) -> ImportConflictBatchApplyReportSnapshot {
        let isAskPerItem = request.duplicateStrategy == .askPerItem && request.sameNameStrategy == .askPerItem
        return ImportConflictBatchApplyReportSnapshot(
            importSessionID: request.importSessionID,
            requestedConflictCount: Int64(request.conflictIDs.count),
            resolvedCount: isAskPerItem ? 0 : Int64(request.conflictIDs.count),
            skippedCount: 0, keptBothCount: 0,
            replacedCount: isAskPerItem ? 0 : Int64(request.conflictIDs.count),
            queuedForPerItemCount: isAskPerItem ? Int64(request.conflictIDs.count) : 0,
            pendingCount: 0, failedCount: 0,
            itemResults: request.conflictIDs.map { conflictID in
                let type: ImportConflictBatchConflictTypeSnapshot = conflictID.hasPrefix("name")
                    ? .sameNameDifferentContent
                    : .duplicateHash
                return ImportConflictBatchItemResultSnapshot(
                    conflictID: conflictID,
                    conflictType: type,
                    appliedStrategy: request.duplicateStrategy,
                    status: isAskPerItem ? .queuedForPerItem : .replaced,
                    fileID: isAskPerItem ? nil : 42,
                    finalPath: "finance/Invoice_2026Q1.pdf",
                    error: nil
                )
            },
            affectedFileIDs: isAskPerItem ? [] : [42],
            undoToken: isAskPerItem ? nil : "undo-import-conflict-batch",
            changeLogActions: isAskPerItem ? [] : ["import_conflict_batch"],
            failureSummary: nil
        )
    }
}

extension UndoActionRecordSnapshot {
    static func importConflictBatchIntegrationAction() -> UndoActionRecordSnapshot {
        importConflictBatchUndoAction()
    }
}

extension UndoActionResultSnapshot {
    static func importConflictBatchIntegrationResult() -> UndoActionResultSnapshot {
        importConflictBatchUndoResult()
    }
}
