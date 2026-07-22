import Foundation

@MainActor
extension ImportBatchCopyImportModel {
    func updateDuplicateStrategy(
        for rowID: ImportBatchCopyImportRow.ID,
        strategy: ImportBatchDuplicateResolutionStrategy
    ) {
        guard canSelectDuplicateStrategy(strategy) else { return }
        guard let row = rows.first(where: { $0.id == rowID }) else { return }
        guard case let .duplicate(existingPath, _, isReplaceConfirmed) = row.status else { return }
        setStatus(.duplicate(
            existingPath: existingPath,
            strategy: strategy,
            isReplaceConfirmed: strategy == .replace ? isReplaceConfirmed : false
        ), for: rowID)
    }

    func updateNameConflictResolution(
        for rowID: ImportBatchCopyImportRow.ID,
        resolution: ImportBatchNameConflictResolution
    ) {
        guard canSelectNameConflictResolution(resolution) else { return }
        guard let row = rows.first(where: { $0.id == rowID }) else { return }
        guard case let .nameConflict(existingPath, _) = row.status else { return }
        setStatus(.nameConflict(existingPath: existingPath, resolution: resolution), for: rowID)
    }

    var showsCoreConflictBatchReview: Bool {
        request?.importConflictBatchRoute != nil
    }

    var conflictBatchPreviewReport: ImportConflictBatchPreviewReportSnapshot? {
        if hasEmptyManualConflictBatchScope {
            return emptyManualConflictBatchPreview()
        }
        return conflictBatchPreviewState.report
    }

    var conflictBatchFailure: CoreErrorMappingSnapshot? {
        conflictBatchPreviewState.failure ?? conflictBatchApplyResult?.failure
    }

    var currentConflictBatchIDs: [String] {
        if appliesConflictBatchToAll {
            return coreConflictBatchRows.map(\.id).sorted()
        }
        return selectedConflictBatchIDs.sorted()
    }

    var normalizedImportConflictBatchSessionID: String? {
        let trimmed = request?.importSessionID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    var coreConflictBatchRows: [ImportConflictBatchPreviewItemSnapshot] {
        if let preview = conflictBatchPreviewReport {
            return preview.items
        }
        let conflictIDs = request?.importConflictIDs ?? []
        return conflictIDs.map { conflictID in
            ImportConflictBatchPreviewItemSnapshot.pendingPlaceholder(conflictID: conflictID)
        }
    }

    var currentConflictBatchApplyRequestIsValid: Bool {
        guard let preview = conflictBatchPreviewReport,
              let request = makeImportConflictBatchApplyRequest(
                  replaceConfirmed: isConflictBatchReplaceConfirmed
              ) else { return false }
        return ImportConflictBatchValidation.canApply(
            preview: preview,
            request: request,
            isApplying: isConflictBatchApplying
        )
    }

    func loadImportConflictBatchPreview() async {
        guard let request = makeImportConflictBatchPreviewRequest() else {
            resetConflictBatchOutcome()
            if !hasEmptyManualConflictBatchScope {
                conflictBatchPreviewState = .idle
            }
            return
        }
        isConflictBatchReplaceConfirmed = false
        resetConflictBatchOutcome()
        conflictBatchPreviewState = .loading(previous: conflictBatchPreviewState.report)
        conflictBatchPreviewState = await ImportConflictBatchAction.preview(
            repoPath: self.request?.repoPath ?? "",
            request: request,
            batcher: conflictBatcher,
            errorMapper: errorMapper,
            previous: conflictBatchPreviewState.report
        )
    }

    func refreshImportConflictBatchPreview() async {
        await loadImportConflictBatchPreview()
    }

    func updateConflictBatchDuplicateStrategy(_ strategy: ImportConflictBatchStrategySnapshot) {
        conflictBatchDuplicateStrategy = strategy
        isConflictBatchReplaceConfirmed = false
        resetConflictBatchOutcome()
    }

    func updateConflictBatchSameNameStrategy(_ strategy: ImportConflictBatchStrategySnapshot) {
        conflictBatchSameNameStrategy = strategy
        isConflictBatchReplaceConfirmed = false
        resetConflictBatchOutcome()
    }

    func updateConflictBatchScope(appliesToAll: Bool) {
        appliesConflictBatchToAll = appliesToAll
        isConflictBatchReplaceConfirmed = false
        if appliesToAll {
            selectedConflictBatchIDs = []
        }
        resetConflictBatchOutcome()
    }

    func setConflictBatchItemSelected(_ conflictID: String, isSelected: Bool) {
        if isSelected {
            selectedConflictBatchIDs.insert(conflictID)
        } else {
            selectedConflictBatchIDs.remove(conflictID)
        }
        isConflictBatchReplaceConfirmed = false
        resetConflictBatchOutcome()
    }

    func confirmConflictBatchReplace() {
        isConflictBatchReplaceConfirmed = true
    }

    func cancelConflictBatchReplace() {
        isConflictBatchReplaceConfirmed = false
        if conflictBatchDuplicateStrategy == .replace {
            conflictBatchDuplicateStrategy = .skip
        }
        if conflictBatchSameNameStrategy == .replace {
            conflictBatchSameNameStrategy = .keepBoth
        }
        resetConflictBatchOutcome()
    }

    func askConflictBatchPerItem() async -> ImportConflictBatchApplyResult? {
        guard let previewRequest = makeImportConflictBatchPreviewRequest(duplicateStrategy: .askPerItem,
                                                                         sameNameStrategy: .askPerItem)
        else { return nil }
        let previousPreview = conflictBatchPreviewReport
        if let previousPreview,
           !ImportConflictBatchValidation.canAskPerItem(preview: previousPreview, isApplying: isConflictBatchApplying) {
            return nil
        }
        resetConflictBatchOutcome()
        isConflictBatchApplying = true
        defer { isConflictBatchApplying = false }
        conflictBatchPreviewState = .loading(previous: previousPreview)
        conflictBatchPreviewState = await ImportConflictBatchAction.preview(
            repoPath: request?.repoPath ?? "",
            request: previewRequest,
            batcher: conflictBatcher,
            errorMapper: errorMapper,
            previous: previousPreview
        )
        guard let preview = conflictBatchPreviewState.report,
              let queue = ImportConflictBatchPerItemQueue.make(from: preview) else { return nil }
        let applyRequest = ImportConflictBatchApplyRequestSnapshot(
            importSessionID: previewRequest.importSessionID,
            conflictIDs: previewRequest.conflictIDs,
            duplicateStrategy: .askPerItem,
            sameNameStrategy: .askPerItem,
            applyToAllSimilarConflicts: previewRequest.applyToAllSimilarConflicts,
            replaceConfirmed: false
        )
        guard ImportConflictBatchValidation.canApply(
            preview: preview,
            request: applyRequest,
            isApplying: false
        ) else { return nil }
        let result = await ImportConflictBatchAction.apply(
            repoPath: request?.repoPath ?? "",
            request: applyRequest,
            preview: preview,
            batcher: conflictBatcher,
            errorMapper: errorMapper
        )
        return await finishConflictBatchPerItem(result: result, queue: queue)
    }

    func makeImportConflictBatchPreviewRequest(
        duplicateStrategy: ImportConflictBatchStrategySnapshot? = nil,
        sameNameStrategy: ImportConflictBatchStrategySnapshot? = nil
    ) -> ImportConflictBatchPreviewRequestSnapshot? {
        guard let importSessionID = normalizedImportConflictBatchSessionID else { return nil }
        let conflictIDs = currentConflictBatchIDs
        guard !conflictIDs.isEmpty else { return nil }
        return ImportConflictBatchPreviewRequestSnapshot(
            importSessionID: importSessionID,
            conflictIDs: conflictIDs,
            duplicateStrategy: duplicateStrategy ?? conflictBatchDuplicateStrategy,
            sameNameStrategy: sameNameStrategy ?? conflictBatchSameNameStrategy,
            applyToAllSimilarConflicts: appliesConflictBatchToAll
        )
    }

    func makeImportConflictBatchApplyRequest(replaceConfirmed: Bool) -> ImportConflictBatchApplyRequestSnapshot? {
        guard let previewRequest = makeImportConflictBatchPreviewRequest() else { return nil }
        return ImportConflictBatchApplyRequestSnapshot(
            importSessionID: previewRequest.importSessionID,
            conflictIDs: previewRequest.conflictIDs,
            duplicateStrategy: previewRequest.duplicateStrategy,
            sameNameStrategy: previewRequest.sameNameStrategy,
            applyToAllSimilarConflicts: previewRequest.applyToAllSimilarConflicts,
            replaceConfirmed: replaceConfirmed
        )
    }

    func applyImportConflictBatchReportToRows(_ report: ImportConflictBatchApplyReportSnapshot) {
        let resultsByID = Dictionary(uniqueKeysWithValues: report.itemResults.map { ($0.conflictID, $0) })
        for row in rows {
            guard let result = resultsByID[row.id] else { continue }
            setStatus(status(for: result, fallback: row.status), for: row.id)
        }
    }

    private func finishConflictBatchPerItem(
        result: ImportConflictBatchApplyResult,
        queue: ImportConflictBatchPerItemQueue
    ) async -> ImportConflictBatchApplyResult {
        conflictBatchApplyResult = result
        guard let report = result.report, report.queuedForPerItemCount > 0 else {
            conflictBatchUndoState = .idle
            return result
        }
        conflictBatchPerItemQueue = queue
        applyImportConflictBatchReportToRows(report)
        await refreshConflictBatchUndoState(report: report, failure: result.failure)
        return result
    }

    func applyImportConflictBatch(replaceConfirmed: Bool? = nil) async -> ImportConflictBatchApplyResult? {
        guard let preview = conflictBatchPreviewReport,
              let request = makeImportConflictBatchApplyRequest(
                  replaceConfirmed: replaceConfirmed ?? isConflictBatchReplaceConfirmed
              ) else { return nil }
        guard ImportConflictBatchValidation.canApply(
            preview: preview,
            request: request,
            isApplying: isConflictBatchApplying
        ) else { return nil }
        isConflictBatchApplying = true
        defer { isConflictBatchApplying = false }
        let result = await ImportConflictBatchAction.apply(
            repoPath: self.request?.repoPath ?? "",
            request: request,
            preview: preview,
            batcher: conflictBatcher,
            errorMapper: errorMapper
        )
        conflictBatchApplyResult = result
        if let report = result.report {
            applyImportConflictBatchReportToRows(report)
            await refreshConflictBatchUndoState(report: report, failure: result.failure)
        } else {
            conflictBatchUndoState = .idle
        }
        return result
    }

    func renameIncomingFile(for rowID: ImportBatchCopyImportRow.ID, to name: String) {
        updateNameConflictResolution(for: rowID, resolution: .renameIncoming(name))
    }

    func beginReplaceConfirmation(for rowID: ImportBatchCopyImportRow.ID)
        -> SingleFileReplaceConfirmationContext? {
        clearReplaceConfirmationRecovery()
        guard let row = rows.first(where: { $0.id == rowID }) else { return nil }
        guard request?.allowReplaceDuringImport == true, request?.isTrashAvailable == true else { return nil }
        guard let existingPath = row.existingConflictPath else { return nil }
        return SingleFileReplaceConfirmationContext(
            existingPath: existingPath,
            incomingPath: row.sourceURL.path,
            incomingSizeBytes: row.sizeBytes,
            targetRelativePath: targetRelativePath(for: row, destination: selectedDestination),
            isTrashAvailable: true
        )
    }

    func applyReplaceConfirmation(
        for rowID: ImportBatchCopyImportRow.ID,
        decision: SingleFileReplaceConfirmationDecision
    ) -> Bool {
        guard decision.understandsReplace else {
            recordReplaceConfirmationFailure(L10n.string("import.replace.checkboxRequired"))
            return false
        }
        guard let expected = currentReplaceConfirmationContext(for: rowID), expected == decision.context else {
            recordReplaceConfirmationFailure("Replace confirmation context expired")
            return false
        }
        guard let row = rows.first(where: { $0.id == rowID }) else { return false }

        switch row.status {
        case let .duplicate(existingPath, .replace, _):
            setStatus(.duplicate(
                existingPath: existingPath,
                strategy: .replace,
                isReplaceConfirmed: true
            ), for: rowID)
        case let .nameConflict(existingPath, .replace):
            setStatus(.nameConflict(
                existingPath: existingPath,
                resolution: .replace(isConfirmed: true)
            ), for: rowID)
        case .loading, .ready, .duplicate, .nameConflict, .iCloudPlaceholder, .blocked, .importing,
             .skippedDuplicate, .skippedICloud, .imported, .error:
            recordReplaceConfirmationFailure("Replace confirmation context expired")
            return false
        }
        clearReplaceConfirmationRecovery()
        return true
    }

    private func canSelectDuplicateStrategy(_ strategy: ImportBatchDuplicateResolutionStrategy) -> Bool {
        strategy != .replace || replaceOptionVisibility == .enabled
    }

    private func canSelectNameConflictResolution(_ resolution: ImportBatchNameConflictResolution) -> Bool {
        !resolution.isReplace || replaceOptionVisibility == .enabled
    }

    private func status(for result: ImportConflictBatchItemResultSnapshot,
                        fallback: ImportBatchCopyImportRowStatus) -> ImportBatchCopyImportRowStatus {
        switch result.status {
        case .skipped:
            .skippedDuplicate(existingPath: result.finalPath ?? existingPath(from: fallback))
        case .keptBoth, .replaced:
            .imported
        case .queuedForPerItem, .pending:
            fallback
        case .failed:
            .error(result.error ?? L10n.string("Import conflict strategy failed."))
        }
    }

    private func existingPath(from status: ImportBatchCopyImportRowStatus) -> String {
        switch status {
        case let .duplicate(existingPath, _, _), let .nameConflict(existingPath, _),
             let .skippedDuplicate(existingPath):
            existingPath
        case .loading, .ready, .iCloudPlaceholder, .blocked, .importing, .skippedICloud, .imported, .error:
            "existing file"
        }
    }

    func currentReplaceConfirmationContext(for rowID: ImportBatchCopyImportRow
        .ID) -> SingleFileReplaceConfirmationContext? {
        guard let row = rows.first(where: { $0.id == rowID }) else { return nil }
        guard request?.allowReplaceDuringImport == true, request?.isTrashAvailable == true else { return nil }
        guard let existingPath = row.existingConflictPath else { return nil }
        return SingleFileReplaceConfirmationContext(
            existingPath: existingPath,
            incomingPath: row.sourceURL.path,
            incomingSizeBytes: row.sizeBytes,
            targetRelativePath: targetRelativePath(for: row, destination: selectedDestination),
            isTrashAvailable: true
        )
    }
}
