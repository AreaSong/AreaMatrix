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
            return await .failed(mapError(error, errorMapper: errorMapper), previous: previous)
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
                failure: mapError(failure, errorMapper: errorMapper)
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
                failure: mapError(error, errorMapper: errorMapper)
            )
        }
    }

    private static func mapError(_ error: Error, errorMapper: any CoreErrorMapping) async -> CoreErrorMappingSnapshot {
        if let coreError = error as? CoreError { return await errorMapper.mapCoreError(coreError) }
        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
    }
}

enum ImportConflictBatchValidation {
    static func actionableIncludedCount(preview: ImportConflictBatchPreviewReportSnapshot) -> Int64 {
        Int64(preview.items.filter { item in
            item.status == .ready || item.status == .needsConfirmation
        }.count)
    }

    static func canApply(
        preview: ImportConflictBatchPreviewReportSnapshot?,
        request: ImportConflictBatchApplyRequestSnapshot,
        isApplying: Bool
    ) -> Bool {
        guard !isApplying,
              let preview,
              !preview.previewToken.isEmpty,
              preview.importSessionID == request.importSessionID,
              actionableIncludedCount(preview: preview) > 0 else { return false }
        if preview.replaceConfirmationRequired && !request.replaceConfirmed {
            return false
        }
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
                guard item.status == .ready || item.status == .needsConfirmation else { return true }
                switch item.conflictType {
                case .duplicateHash:
                    return item.selectedStrategy == request.duplicateStrategy
                case .sameNameDifferentContent:
                    return item.selectedStrategy == request.sameNameStrategy
                }
            }
    }
}

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
        conflictBatchPreviewState.report
    }

    var conflictBatchFailure: CoreErrorMappingSnapshot? {
        conflictBatchPreviewState.failure ?? conflictBatchApplyResult?.failure
    }

    var conflictBatchScopeSummary: String {
        guard let preview = conflictBatchPreviewReport else { return "Checking conflicts..." }
        if preview.applyToAllSimilarConflicts {
            return "Will apply to \(preview.duplicateConflictCount) duplicate conflicts and " +
                "\(preview.sameNameConflictCount) same-name conflicts."
        }
        return "Will apply to \(preview.includedCount) selected conflicts."
    }

    var conflictBatchApplyDisabledReason: String? {
        if isConflictBatchApplying { return "Applying..." }
        guard let preview = conflictBatchPreviewReport else { return "Checking conflicts..." }
        if !preview.canApply && ImportConflictBatchValidation.actionableIncludedCount(preview: preview) == 0 {
            return preview.applyBlockedReason ?? "Could not prepare conflict strategy."
        }
        if ImportConflictBatchValidation.actionableIncludedCount(preview: preview) == 0 {
            return "All conflicts in this scope are blocked."
        }
        let replaceConfirmed = isConflictBatchReplaceConfirmed || preview.replaceConfirmationRequired
        guard let request = makeImportConflictBatchApplyRequest(replaceConfirmed: replaceConfirmed),
              ImportConflictBatchValidation.canApply(
                  preview: preview,
                  request: request,
                  isApplying: false
              ) else {
            return "Refresh conflict strategy preview."
        }
        return nil
    }

    var conflictBatchAskPerItemDisabledReason: String? {
        if isConflictBatchApplying { return "Applying..." }
        guard let preview = conflictBatchPreviewReport else { return "Checking conflicts..." }
        if ImportConflictBatchValidation.canAskPerItem(preview: preview, isApplying: false) { return nil }
        if preview.includedCount > 0 {
            return "All conflicts in this scope are blocked."
        }
        return preview.applyBlockedReason ?? "Select at least one conflict."
    }

    var currentConflictBatchIDs: [String] {
        if appliesConflictBatchToAllSimilarConflicts {
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
            conflictBatchPreviewState = .idle
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
        appliesConflictBatchToAllSimilarConflicts = appliesToAll
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
        let previousDuplicate = conflictBatchDuplicateStrategy
        let previousSameName = conflictBatchSameNameStrategy
        conflictBatchDuplicateStrategy = .askPerItem
        conflictBatchSameNameStrategy = .askPerItem
        await loadImportConflictBatchPreview()
        let result = await applyImportConflictBatch(replaceConfirmed: false)
        conflictBatchDuplicateStrategy = previousDuplicate
        conflictBatchSameNameStrategy = previousSameName
        return result
    }

    func makeImportConflictBatchPreviewRequest() -> ImportConflictBatchPreviewRequestSnapshot? {
        guard let importSessionID = normalizedImportConflictBatchSessionID else { return nil }
        let conflictIDs = currentConflictBatchIDs
        guard !conflictIDs.isEmpty else { return nil }
        return ImportConflictBatchPreviewRequestSnapshot(
            importSessionID: importSessionID,
            conflictIDs: conflictIDs,
            duplicateStrategy: conflictBatchDuplicateStrategy,
            sameNameStrategy: conflictBatchSameNameStrategy,
            applyToAllSimilarConflicts: appliesConflictBatchToAllSimilarConflicts
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
            recordReplaceConfirmationFailure("Replace 需要先勾选二次确认")
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

    func downloadICloudPlaceholderAndRetry(rowID: ImportBatchCopyImportRow.ID) async -> Bool {
        guard let row = rows.first(where: { $0.id == rowID }) else { return false }
        guard case let .iCloudPlaceholder(path, _) = row.status else { return false }
        isICloudDownloading = true
        defer { isICloudDownloading = false }

        do {
            try await placeholderDownloader.downloadPlaceholder(at: row.sourceURL)
            setStatus(.loading, for: rowID)
            return true
        } catch {
            setStatus(.iCloudPlaceholder(
                path: path,
                message: "iCloud 下载失败：\(error.localizedDescription)"
            ), for: rowID)
            return false
        }
    }

    func downloadAllICloudPlaceholdersAndRetry() async -> Bool {
        var didDownload = false
        for row in rows {
            if case .iCloudPlaceholder = row.status {
                didDownload = await downloadICloudPlaceholderAndRetry(rowID: row.id) || didDownload
            }
        }
        return didDownload
    }

    func markICloudPlaceholderPending(rowID: ImportBatchCopyImportRow.ID) {
        guard let row = rows.first(where: { $0.id == rowID }) else { return }
        guard case let .iCloudPlaceholder(path, _) = row.status else { return }
        setStatus(.skippedICloud(path: path), for: rowID)
    }

    private func canSelectDuplicateStrategy(_ strategy: ImportBatchDuplicateResolutionStrategy) -> Bool {
        strategy != .replace || replaceOptionVisibility == .enabled
    }

    private func canSelectNameConflictResolution(_ resolution: ImportBatchNameConflictResolution) -> Bool {
        !resolution.isReplace || replaceOptionVisibility == .enabled
    }

    private func status(
        for result: ImportConflictBatchItemResultSnapshot,
        fallback: ImportBatchCopyImportRowStatus
    ) -> ImportBatchCopyImportRowStatus {
        switch result.status {
        case .skipped:
            return .skippedDuplicate(existingPath: result.finalPath ?? existingPath(from: fallback))
        case .keptBoth, .replaced:
            return .imported
        case .queuedForPerItem, .pending:
            return fallback
        case .failed:
            return .error(result.error ?? "Import conflict strategy failed.")
        }
    }

    private func existingPath(from status: ImportBatchCopyImportRowStatus) -> String {
        switch status {
        case let .duplicate(existingPath, _, _), let .nameConflict(existingPath, _),
             let .skippedDuplicate(existingPath):
            return existingPath
        case .loading, .ready, .iCloudPlaceholder, .blocked, .importing, .skippedICloud, .imported, .error:
            return "existing file"
        }
    }

    private func currentReplaceConfirmationContext(
        for rowID: ImportBatchCopyImportRow.ID
    ) -> SingleFileReplaceConfirmationContext? {
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
