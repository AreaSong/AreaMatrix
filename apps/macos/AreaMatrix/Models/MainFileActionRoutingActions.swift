import Foundation

extension MainFileListModel {
    func beginRename(fileID: Int64? = nil) {
        guard let fileID = fileID ?? selection.singleFileID,
              writeActionDisabledReason(fileID: fileID) == nil else { return }
        renameState = .idle
        pendingActionDestination = .rename(fileID: fileID)
    }

    func beginChangeCategory(fileID: Int64? = nil) {
        guard let fileID = fileID ?? selection.singleFileID,
              writeActionDisabledReason(fileID: fileID) == nil else { return }
        changeCategoryState = .idle
        pendingActionDestination = .changeCategory(fileID: fileID)
    }

    func beginRenameFromChangeCategory(fileID: Int64, targetCategory: String) {
        guard pendingActionDestination?.isChangeCategory(fileID: fileID) == true,
              writeActionDisabledReason(fileID: fileID) == nil,
              !changeCategoryState.isMoving(fileID: fileID) else { return }
        renameState = .returningToChangeCategory(fileID: fileID, targetCategory: targetCategory)
        pendingActionDestination = .rename(fileID: fileID)
    }

    func beginDelete(fileID: Int64? = nil) {
        guard let fileID = fileID ?? selection.singleFileID,
              writeActionDisabledReason(fileID: fileID) == nil else { return }
        pendingActionDestination = .delete(fileID: fileID)
    }

    func beginICloudConflictResolution(fileID: Int64? = nil) {
        guard let fileID = fileID ?? selection.singleFileID,
              let file = file(for: fileID),
              file.hasICloudConflictCopySignal,
              writeActionDisabledReason(fileID: fileID) == nil else { return }
        iCloudConflictResolutionState = .idle
        pendingActionDestination = .iCloudConflict(fileID: fileID)
    }

    func openClassifierRuleEditorForBatchCategory(context: BatchChangeCategoryNewCategoryReturnContext) {
        pendingSearchDestination = .classifierRuleEditor(context: context)
    }

    func applyICloudConflictResolution(
        fileID: Int64,
        strategy: ICloudConflictResolutionStrategy,
        originalPath: String?,
        conflictedCopyPath: String?
    ) async {
        guard pendingActionDestination == .iCloudConflict(fileID: fileID) else { return }
        guard !iCloudConflictResolutionState.isApplying,
              writeActionDisabledReason(fileID: fileID) == nil else { return }

        if let blocker = iCloudConflictResolver.iCloudConflictResolutionCapability.blocker {
            let mapping = await mapCoreError(blocker.coreError)
            iCloudConflictResolutionState = .failed(fileID: fileID, strategy: strategy, mapping)
            return
        }

        iCloudConflictResolutionState = .applying(fileID: fileID, strategy: strategy)
        clearDiagnosticsState()
        do {
            let result = try await iCloudConflictResolver.resolveICloudConflict(ICloudConflictResolutionRequest(
                repoPath: repoPath,
                fileID: fileID,
                strategy: strategy,
                originalPath: originalPath,
                conflictedCopyPath: conflictedCopyPath
            ))
            try validateICloudConflictResolution(result, fileID: fileID)
            await refreshAfterICloudConflictResolution(fileID: result.focusFileID ?? fileID, strategy: strategy)
        } catch {
            let mapping = await mapCoreError(error)
            guard pendingActionDestination == .iCloudConflict(fileID: fileID) else { return }
            iCloudConflictResolutionState = .failed(fileID: fileID, strategy: strategy, mapping)
        }
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
        let file = file(for: fileID)
        return (
            ICloudConflictVersionSnapshot.originalCandidate(repoPath: repoPath, file: file).path,
            ICloudConflictVersionSnapshot.conflictedCandidate(repoPath: repoPath, file: file).path
        )
    }

    private func validateICloudConflictResolution(
        _ result: ICloudConflictResolutionResult,
        fileID: Int64
    ) throws {
        guard result.didClearConflictState else {
            throw CoreError.Internal(message: "iCloud conflict \(fileID) did not clear conflict state")
        }
        guard result.didWriteChangeLog else {
            throw CoreError.Internal(message: "iCloud conflict \(fileID) did not write change_log")
        }
    }

    private func refreshAfterICloudConflictResolution(
        fileID: Int64,
        strategy: ICloudConflictResolutionStrategy
    ) async {
        await loadCurrentCategory(currentCategory, focusingOn: fileID)
        if selection.singleFileID == fileID {
            await loadChangeLog(fileID: fileID)
        }
        iCloudConflictResolutionState = .idle
        pendingActionDestination = nil
        statusBanner = .resolvedICloudConflict(fileID: fileID, strategy: strategy)
    }

    func clearPendingActionDestination() {
        if !renameState.isRenaming,
           !deleteState.isDeleting,
           !isMovingCategory,
           !iCloudConflictResolutionState.isApplying {
            pendingActionDestination = nil
            renameState = .idle
            deleteState = .idle
            changeCategoryState = .idle
            iCloudConflictResolutionState = .idle
        }
    }

    private var isMovingCategory: Bool {
        guard let destination = pendingActionDestination else { return false }
        return changeCategoryState.isMoving(fileID: destination.fileID)
    }

    private func file(for fileID: Int64) -> FileEntrySnapshot? {
        files.first { $0.id == fileID } ??
            selectedFileDetail.flatMap { $0.id == fileID ? $0 : nil }
    }
}

extension FileEntrySnapshot {
    var hasICloudConflictCopySignal: Bool {
        let lowercasedName = currentName.lowercased()
        let lowercasedPath = path.lowercased()
        return lowercasedName.contains("conflicted copy") ||
            lowercasedPath.contains("conflicted copy")
    }
}
