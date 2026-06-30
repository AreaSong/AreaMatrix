import Foundation

protocol CoreImportConflictBatching: Sendable {
    func previewImportConflictBatch(
        repoPath: String,
        request: ImportConflictBatchPreviewRequestSnapshot
    ) async throws -> ImportConflictBatchPreviewReportSnapshot

    func applyImportConflictBatch(
        repoPath: String,
        request: ImportConflictBatchApplyRequestSnapshot,
        previewToken: String
    ) async throws -> ImportConflictBatchApplyReportSnapshot
}

extension CoreBridge: CoreImportConflictBatching {
    func previewImportConflictBatch(
        repoPath: String,
        request: ImportConflictBatchPreviewRequestSnapshot
    ) async throws -> ImportConflictBatchPreviewReportSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try ImportConflictBatchPreviewReportSnapshot(coreReport: AreaMatrix.previewImportConflictBatch(
                repoPath: repoPath,
                request: ImportConflictBatchPreviewRequest(snapshot: request)
            ))
        }.value
    }

    func applyImportConflictBatch(
        repoPath: String,
        request: ImportConflictBatchApplyRequestSnapshot,
        previewToken: String
    ) async throws -> ImportConflictBatchApplyReportSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try ImportConflictBatchApplyReportSnapshot(coreReport: AreaMatrix.applyImportConflictBatch(
                repoPath: repoPath,
                request: ImportConflictBatchApplyRequest(snapshot: request),
                previewToken: previewToken
            ))
        }.value
    }
}

private extension ImportConflictBatchPreviewRequest {
    init(snapshot: ImportConflictBatchPreviewRequestSnapshot) {
        self.init(
            importSessionId: snapshot.importSessionID,
            conflictIds: snapshot.conflictIDs,
            duplicateStrategy: ImportConflictBatchStrategy(snapshotValue: snapshot.duplicateStrategy),
            sameNameStrategy: ImportConflictBatchStrategy(snapshotValue: snapshot.sameNameStrategy),
            applyToAllSimilarConflicts: snapshot.applyToAllSimilarConflicts
        )
    }
}

private extension ImportConflictBatchApplyRequest {
    init(snapshot: ImportConflictBatchApplyRequestSnapshot) {
        self.init(
            importSessionId: snapshot.importSessionID,
            conflictIds: snapshot.conflictIDs,
            duplicateStrategy: ImportConflictBatchStrategy(snapshotValue: snapshot.duplicateStrategy),
            sameNameStrategy: ImportConflictBatchStrategy(snapshotValue: snapshot.sameNameStrategy),
            applyToAllSimilarConflicts: snapshot.applyToAllSimilarConflicts,
            replaceConfirmed: snapshot.replaceConfirmed
        )
    }
}

private extension ImportConflictBatchStrategy {
    init(snapshotValue: ImportConflictBatchStrategySnapshot) {
        switch snapshotValue {
        case .skip:
            self = .skip
        case .keepBoth:
            self = .keepBoth
        case .replace:
            self = .replace
        case .askPerItem:
            self = .askPerItem
        }
    }
}

private extension ImportConflictBatchStrategySnapshot {
    init(coreStrategy: ImportConflictBatchStrategy) {
        switch coreStrategy {
        case .skip:
            self = .skip
        case .keepBoth:
            self = .keepBoth
        case .replace:
            self = .replace
        case .askPerItem:
            self = .askPerItem
        }
    }
}

private extension ImportConflictBatchPreviewReportSnapshot {
    init(coreReport: ImportConflictBatchPreviewReport) {
        importSessionID = coreReport.importSessionId
        previewToken = coreReport.previewToken
        applyToAllSimilarConflicts = coreReport.applyToAllSimilarConflicts
        requestedConflictCount = coreReport.requestedConflictCount
        duplicateConflictCount = coreReport.duplicateConflictCount
        sameNameConflictCount = coreReport.sameNameConflictCount
        includedCount = coreReport.includedCount
        pendingCount = coreReport.pendingCount
        blockedCount = coreReport.blockedCount
        replaceCount = coreReport.replaceCount
        skipCount = coreReport.skipCount
        keepBothCount = coreReport.keepBothCount
        askPerItemCount = coreReport.askPerItemCount
        trashAvailable = coreReport.trashAvailable
        undoAvailable = coreReport.undoAvailable
        canApply = coreReport.canApply
        applyBlockedReason = coreReport.applyBlockedReason
        replaceConfirmationRequired = coreReport.replaceConfirmationRequired
        replaceConfirmationSummary = coreReport.replaceConfirmationSummary
        items = coreReport.items.map(ImportConflictBatchPreviewItemSnapshot.init(coreItem:))
    }
}

private extension ImportConflictBatchPreviewItemSnapshot {
    init(coreItem: ImportConflictBatchPreviewItem) {
        conflictID = coreItem.conflictId
        conflictType = ImportConflictBatchConflictTypeSnapshot(coreType: coreItem.conflictType)
        existingFileID = coreItem.existingFileId
        existingPath = coreItem.existingPath
        incomingPath = coreItem.incomingPath
        targetPath = coreItem.targetPath
        selectedStrategy = ImportConflictBatchStrategySnapshot(coreStrategy: coreItem.selectedStrategy)
        status = ImportConflictBatchPreviewStatusSnapshot(coreStatus: coreItem.status)
        willReplace = coreItem.willReplace
        willKeepBoth = coreItem.willKeepBoth
        willSkip = coreItem.willSkip
        willAskPerItem = coreItem.willAskPerItem
        indexOnly = coreItem.indexOnly
        riskSummary = coreItem.riskSummary
        reason = coreItem.reason
    }
}

private extension ImportConflictBatchApplyReportSnapshot {
    init(coreReport: ImportConflictBatchApplyReport) {
        importSessionID = coreReport.importSessionId
        requestedConflictCount = coreReport.requestedConflictCount
        resolvedCount = coreReport.resolvedCount
        skippedCount = coreReport.skippedCount
        keptBothCount = coreReport.keptBothCount
        replacedCount = coreReport.replacedCount
        queuedForPerItemCount = coreReport.queuedForPerItemCount
        pendingCount = coreReport.pendingCount
        failedCount = coreReport.failedCount
        itemResults = coreReport.itemResults.map(ImportConflictBatchItemResultSnapshot.init(coreResult:))
        affectedFileIDs = coreReport.affectedFileIds
        undoToken = coreReport.undoToken
        changeLogActions = coreReport.changeLogActions
        failureSummary = coreReport.failureSummary
    }
}

private extension ImportConflictBatchItemResultSnapshot {
    init(coreResult: ImportConflictBatchItemResult) {
        conflictID = coreResult.conflictId
        conflictType = ImportConflictBatchConflictTypeSnapshot(coreType: coreResult.conflictType)
        appliedStrategy = ImportConflictBatchStrategySnapshot(coreStrategy: coreResult.appliedStrategy)
        status = ImportConflictBatchResultStatusSnapshot(coreStatus: coreResult.status)
        fileID = coreResult.fileId
        finalPath = coreResult.finalPath
        error = coreResult.error
    }
}

private extension ImportConflictBatchConflictTypeSnapshot {
    init(coreType: ImportConflictBatchConflictType) {
        switch coreType {
        case .duplicateHash:
            self = .duplicateHash
        case .sameNameDifferentContent:
            self = .sameNameDifferentContent
        }
    }
}

private extension ImportConflictBatchPreviewStatusSnapshot {
    init(coreStatus: ImportConflictBatchPreviewStatus) {
        switch coreStatus {
        case .ready:
            self = .ready
        case .pending:
            self = .pending
        case .needsConfirmation:
            self = .needsConfirmation
        case .blocked:
            self = .blocked
        case .failed:
            self = .failed
        }
    }
}

private extension ImportConflictBatchResultStatusSnapshot {
    init(coreStatus: ImportConflictBatchResultStatus) {
        switch coreStatus {
        case .skipped:
            self = .skipped
        case .keptBoth:
            self = .keptBoth
        case .replaced:
            self = .replaced
        case .queuedForPerItem:
            self = .queuedForPerItem
        case .pending:
            self = .pending
        case .failed:
            self = .failed
        }
    }
}
