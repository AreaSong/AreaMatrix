import Foundation

extension MainFileListModel {
    func applyCategoryMoveOutcome(_ outcome: FileActionCategoryOutcome) async {
        fileActionCoordinator.classifierCorrectionResult = outcome.correction
        let movedFile = outcome.file
        files = files.map { $0.id == movedFile.id ? movedFile : $0 }
        if currentCategory != nil, movedFile.category != currentCategory { files.removeAll { $0.id == movedFile.id } }
        selection = .single(movedFile.id)
        selectedFileDetail = movedFile
        selectedFileNoteWriteBlock = noteWriteBlock(for: movedFile)
        detailErrorMapping = nil
        isDetailLoading = false
        statusBanner = outcome.mode == .classifierCorrection
            ? .correctedClassification(
                fileID: movedFile.id,
                category: movedFile.category,
                ruleConfirmationRequired: outcome.correction?.ruleConfirmationRequired ?? false
            )
            : .changedCategory(fileID: movedFile.id, category: movedFile.category)
        await loadChangeLog(fileID: movedFile.id)
        detailTabRequest = .automatic(.log)
    }

    func applyAIClassificationOutcome(
        _ outcome: FileActionCategoryOutcome,
        request: AIClassificationSuggestionApplyRequest
    ) async {
        await applyCategoryMoveOutcome(outcome)
        guard request.rememberRule,
              let handoff = fileActionCoordinator.makeClassifierRuleHandoff(
                  file: outcome.file,
                  targetCategory: outcome.file.category,
                  moveFile: request.moveFile,
                  sourcePageID: "ai-category-suggestion",
                  aiProvenance: ClassifierRuleAIProvenance(
                      suggestion: request.suggestion,
                      finalCategory: outcome.file.category
                  )
              ) else {
            fileActionCoordinator.pendingActionDestination = .aiClassificationSuggestion(
                fileID: outcome.file.id,
                returnContext: AIClassificationSuggestionReturnContext(
                    appliedCategory: outcome.file.category,
                    callLogID: request.suggestion.callLogID,
                    ruleStatus: nil
                )
            )
            return
        }
        fileActionCoordinator.beginClassifierRuleRoute(.saveRule(handoff), handoff: handoff)
    }

    func applySearchResult(_ result: SearchResultApplication) {
        switch result {
        case .loading:
            isLoading = true; errorMapping = nil; currentListDiagnostics.clear()
        case let .loaded(files):
            self.files = files; isLoading = false; errorMapping = nil
        case .failed:
            isLoading = false
        case .cleared:
            isLoading = false; errorMapping = nil; clearDetail()
        }
    }

    var pendingActionDestination: MainFileActionDestination? {
        get { fileActionCoordinator.destination }
        set { fileActionCoordinator.destination = newValue }
    }

    var renameState: MainFileRenameState {
        get { fileActionCoordinator.renameState }
        set { fileActionCoordinator.renameState = newValue }
    }

    var deleteState: MainFileDeleteState {
        get { fileActionCoordinator.deleteState }
        set { fileActionCoordinator.deleteState = newValue }
    }

    var changeCategoryState: MainFileCategoryMoveState {
        get { fileActionCoordinator.changeCategoryState }
        set { fileActionCoordinator.changeCategoryState = newValue }
    }

    var classifierCorrectionContextState: ClassifierCorrectionContextState {
        get { fileActionCoordinator.classifierCorrectionContextState }
        set { fileActionCoordinator.classifierCorrectionContextState = newValue }
    }

    var classifierCorrectionResult: ClassifierCorrectionResultSnapshot? {
        get { fileActionCoordinator.classifierCorrectionResult }
        set { fileActionCoordinator.classifierCorrectionResult = newValue }
    }

    func clearStatusBanner() {
        statusBanner = nil
    }

    func showUnsavedNoteDraftPreserved(fileID: Int64) {
        statusBanner = .unsavedNoteDraftPreserved(fileID: fileID)
    }

    func writeActionDisabledReason(fileID: Int64) -> MainFileWriteActionDisabledReason? {
        MainFileWriteActionEligibility.disabledReason(
            fileID: fileID,
            isReadOnly: isReadOnly,
            isLoading: isLoading,
            writeLockedFileIDs: writeLockedFileIDs
        )
    }

    func canPerformWriteAction(fileID: Int64) -> Bool {
        writeActionDisabledReason(fileID: fileID) == nil
    }

    func writeActionDisabledMessage(fileID: Int64) -> String? {
        writeActionDisabledReason(fileID: fileID)?.message
    }

    func selectedWriteActionDisabledMessage(noSelectionMessage: String) -> String? {
        guard let fileID = selection.singleFileID else { return noSelectionMessage }
        return writeActionDisabledMessage(fileID: fileID)
    }

    func beginAIClassificationSuggestion(fileID: Int64? = nil) {
        guard let fileID = writableActionFileID(fileID) else { return }
        pendingActionDestination = .aiClassificationSuggestion(fileID: fileID)
    }

    func beginRename(fileID: Int64? = nil) {
        guard let fileID = writableActionFileID(fileID) else { return }
        fileActionCoordinator.beginRename(fileID: fileID)
    }

    func beginChangeCategory(fileID: Int64? = nil) {
        guard let fileID = writableActionFileID(fileID) else { return }
        fileActionCoordinator.beginChangeCategory(fileID: fileID)
    }

    func beginClassifierCorrection(fileID: Int64? = nil) {
        guard let fileID = writableActionFileID(fileID) else { return }
        fileActionCoordinator.beginClassifierCorrection(fileID: fileID)
    }

    func beginRenameFromChangeCategory(fileID: Int64, targetCategory: String) {
        guard canPerformWriteAction(fileID: fileID) else { return }
        fileActionCoordinator.beginRenameFromChangeCategory(fileID: fileID, targetCategory: targetCategory)
    }

    func beginDelete(fileID: Int64? = nil) {
        guard let fileID = writableActionFileID(fileID) else { return }
        fileActionCoordinator.beginDelete(fileID: fileID)
    }

    func openClassifierRuleEditorForBatchCategory(context: BatchChangeCategoryReturnContext) {
        searchModel.pendingSearchDestination = .classifierRuleEditor(context: context)
    }

    func clearPendingActionDestination() {
        fileActionCoordinator.clearPendingActionDestination(
            canClearExternalState: !syncConflictCoordinator.resolutionState.isApplying
        )
        if fileActionCoordinator.destination == nil { syncConflictCoordinator.resolutionState = .idle }
    }

    func actionRoutingFile(for fileID: Int64) -> FileEntrySnapshot? {
        files.first { $0.id == fileID } ?? selectedFileDetail.flatMap { $0.id == fileID ? $0 : nil }
    }

    func beginAIClassificationChange(fileID: Int64, targetCategory: String?) {
        guard let fileID = writableActionFileID(fileID) else { return }
        changeCategoryState = .idle
        classifierCorrectionContextState = .idle
        classifierCorrectionResult = nil
        pendingActionDestination = .changeCategory(
            fileID: fileID,
            initialTargetCategory: targetCategory,
            mode: .classifierCorrection
        )
    }

    func writableActionFileID(_ fileID: Int64? = nil) -> Int64? {
        guard let resolvedFileID = fileID ?? selection.singleFileID,
              canPerformWriteAction(fileID: resolvedFileID) else {
            return nil
        }
        return resolvedFileID
    }

    @discardableResult
    func submitDelete(fileID: Int64, operation: MainFileDeleteOperation) async -> Bool {
        guard canPerformWriteAction(fileID: fileID) else { return false }
        let selectionGeneration = detailGeneration
        currentListDiagnostics.clear()
        guard let outcome = await fileActionCoordinator.submitDelete(fileID: fileID, operation: operation) else {
            return false
        }
        files.removeAll { $0.id == outcome.fileID }
        if detailGeneration == selectionGeneration, selection.singleFileID == outcome.fileID {
            await selectFiles([])
        }
        statusBanner = FileActionCoordinator.successBanner(for: outcome.operation, fileID: outcome.fileID)
        return true
    }

    @discardableResult
    func submitRename(fileID: Int64, newName: String) async -> Bool {
        guard canPerformWriteAction(fileID: fileID) else { return false }
        let selectionGeneration = detailGeneration
        guard let outcome = await fileActionCoordinator.submitRename(fileID: fileID, newName: newName) else {
            return false
        }
        let renamedFile = outcome.file
        files = files.map { $0.id == renamedFile.id ? renamedFile : $0 }
        if detailGeneration == selectionGeneration, selection.singleFileID == renamedFile.id {
            selectedFileDetail = renamedFile
            selectedFileNoteWriteBlock = noteWriteBlock(for: renamedFile)
            detailErrorMapping = nil
            isDetailLoading = false
            await loadChangeLog(fileID: renamedFile.id)
            if case let .loaded(loadedFileID, _) = detailLogState, loadedFileID == renamedFile.id {
                detailTabRequest = .automatic(.log)
            }
        }
        statusBanner = .renamedPreservedSelection(fileID: renamedFile.id)
        return true
    }

    var iCloudConflictResolutionState: ICloudConflictResolutionState {
        get { syncConflictCoordinator.resolutionState }
        set { syncConflictCoordinator.resolutionState = newValue }
    }

    func beginICloudConflictResolution(fileID: Int64? = nil) {
        guard let fileID = fileID ?? selection.singleFileID,
              let file = actionRoutingFile(for: fileID),
              file.hasICloudConflictCopySignal,
              canPerformWriteAction(fileID: fileID) else { return }
        syncConflictCoordinator.resolutionState = .idle
        pendingActionDestination = .iCloudConflict(fileID: fileID)
    }

    func applyICloudConflictResolution(
        fileID: Int64,
        strategy: ICloudConflictResolutionStrategy,
        originalPath: String?,
        conflictedCopyPath: String?
    ) async {
        guard pendingActionDestination == .iCloudConflict(fileID: fileID),
              !syncConflictCoordinator.resolutionState.isApplying,
              canPerformWriteAction(fileID: fileID) else { return }
        currentListDiagnostics.clear()
        let conflictID = actionRoutingFile(for: fileID)?.path ?? conflictedCopyPath ?? "\(fileID)"
        guard let result = await syncConflictCoordinator.resolve(SyncConflictResolutionRequestContext(
            fileID: fileID,
            strategy: strategy,
            originalPath: originalPath,
            conflictedCopyPath: conflictedCopyPath,
            conflictID: conflictID,
            isCurrent: { [weak self] in
                self?.pendingActionDestination == .iCloudConflict(fileID: fileID)
            }
        )) else { return }
        await refreshAfterICloudConflictResolution(
            fileID: result.focusFileID ?? fileID,
            strategy: strategy
        )
    }

    func completePreviewedICloudConflictResolution(
        fileID: Int64,
        strategy: ICloudConflictResolutionStrategy,
        report: ICloudConflictResolveReportSnapshot
    ) async {
        guard pendingActionDestination == .iCloudConflict(fileID: fileID),
              await syncConflictCoordinator.validatePreviewedResolution(
                  fileID: fileID,
                  strategy: strategy,
                  report: report
              ) else { return }
        await refreshAfterICloudConflictResolution(fileID: fileID, strategy: strategy)
    }

    func recordICloudConflictResolutionFailure(
        fileID: Int64,
        strategy: ICloudConflictResolutionStrategy,
        mapping: CoreErrorMappingSnapshot
    ) {
        guard pendingActionDestination == .iCloudConflict(fileID: fileID) else { return }
        syncConflictCoordinator.recordICloudConflictResolutionFailure(
            fileID: fileID,
            strategy: strategy,
            mapping: mapping
        )
    }

    func applyKeepBothICloudConflict(fileID: Int64) async {
        let versions = iCloudConflictVersions(for: fileID)
        await applyICloudConflictResolution(
            fileID: fileID,
            strategy: .keepBoth,
            originalPath: versions.original,
            conflictedCopyPath: versions.conflictedCopy
        )
    }

    func iCloudConflictVersions(for fileID: Int64) -> (original: String?, conflictedCopy: String?) {
        syncConflictCoordinator.versions(for: actionRoutingFile(for: fileID))
    }

    private func refreshAfterICloudConflictResolution(
        fileID: Int64,
        strategy: ICloudConflictResolutionStrategy
    ) async {
        await loadCurrentCategory(currentCategory, focusingOn: fileID)
        if selection.singleFileID == fileID { await loadChangeLog(fileID: fileID) }
        syncConflictCoordinator.completeResolution()
        pendingActionDestination = nil
        statusBanner = .resolvedICloudConflict(fileID: fileID, strategy: strategy)
    }
}
