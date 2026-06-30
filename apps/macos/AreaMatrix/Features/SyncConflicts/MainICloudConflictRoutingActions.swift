import Foundation

extension MainFileListModel {
    func beginICloudConflictResolution(fileID: Int64? = nil) {
        guard let fileID = fileID ?? selection.singleFileID,
              let file = actionRoutingFile(for: fileID),
              file.hasICloudConflictCopySignal,
              canPerformWriteAction(fileID: fileID) else { return }
        iCloudConflictResolutionState = .idle
        pendingActionDestination = .iCloudConflict(fileID: fileID)
    }

    func applyICloudConflictResolution(
        fileID: Int64,
        strategy: ICloudConflictResolutionStrategy,
        originalPath: String?,
        conflictedCopyPath: String?
    ) async {
        guard pendingActionDestination == .iCloudConflict(fileID: fileID) else { return }
        guard !iCloudConflictResolutionState.isApplying,
              canPerformWriteAction(fileID: fileID) else { return }

        if let blocker = iCloudConflictResolver.iCloudConflictResolutionCapability.blocker {
            let mapping = await mapCoreError(blocker.coreError)
            iCloudConflictResolutionState = .failed(fileID: fileID, strategy: strategy, mapping)
            return
        }

        iCloudConflictResolutionState = .applying(fileID: fileID, strategy: strategy)
        clearDiagnosticsState()
        do {
            let conflictID = actionRoutingFile(for: fileID)?.path ?? conflictedCopyPath ?? "\(fileID)"
            let result = try await iCloudConflictResolver.resolveICloudConflict(ICloudConflictResolutionRequest(
                repoPath: repoPath,
                conflictID: conflictID,
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

    func completePreviewedICloudConflictResolution(
        fileID: Int64,
        strategy: ICloudConflictResolutionStrategy,
        report: ICloudConflictResolveReportSnapshot
    ) async {
        guard pendingActionDestination == .iCloudConflict(fileID: fileID) else { return }
        let result = ICloudConflictResolutionResult(report: report)
        do {
            try validateICloudConflictResolution(result, fileID: fileID)
            await refreshAfterICloudConflictResolution(fileID: fileID, strategy: strategy)
        } catch {
            let mapping = await mapCoreError(error)
            iCloudConflictResolutionState = .failed(fileID: fileID, strategy: strategy, mapping)
        }
    }

    func recordICloudConflictResolutionFailure(
        fileID: Int64,
        strategy: ICloudConflictResolutionStrategy,
        mapping: CoreErrorMappingSnapshot
    ) {
        guard pendingActionDestination == .iCloudConflict(fileID: fileID) else { return }
        iCloudConflictResolutionState = .failed(fileID: fileID, strategy: strategy, mapping)
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
        let file = actionRoutingFile(for: fileID)
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
}

extension FileEntrySnapshot {
    var hasICloudConflictCopySignal: Bool {
        let lowercasedName = currentName.lowercased()
        let lowercasedPath = path.lowercased()
        return lowercasedName.contains("conflicted copy") ||
            lowercasedPath.contains("conflicted copy")
    }
}
