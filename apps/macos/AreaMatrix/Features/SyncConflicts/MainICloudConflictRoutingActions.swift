import Foundation

struct SyncConflictResolutionRequestContext {
    var fileID: Int64
    var strategy: ICloudConflictResolutionStrategy
    var originalPath: String?
    var conflictedCopyPath: String?
    var conflictID: String
    var isCurrent: @MainActor () -> Bool
}

extension SyncConflictCoordinator {
    func resolve(_ request: SyncConflictResolutionRequestContext) async -> ICloudConflictResolutionResult? {
        guard !resolutionState.isApplying else { return nil }
        if let blocker = resolver.iCloudConflictResolutionCapability.blocker {
            let mapping = await mapCoreError(blocker.error)
            resolutionState = .failed(fileID: request.fileID, strategy: request.strategy, mapping)
            return nil
        }
        resolutionState = .applying(fileID: request.fileID, strategy: request.strategy)
        do {
            let result = try await resolver.resolveICloudConflict(ICloudConflictResolutionRequest(
                repoPath: repoPath,
                conflictID: request.conflictID,
                fileID: request.fileID,
                strategy: request.strategy,
                originalPath: request.originalPath,
                conflictedCopyPath: request.conflictedCopyPath
            ))
            try validateICloudConflictResolution(result, fileID: request.fileID)
            return result
        } catch {
            let mapping = await mapCoreError(error)
            guard request.isCurrent() else { return nil }
            resolutionState = .failed(fileID: request.fileID, strategy: request.strategy, mapping)
            return nil
        }
    }

    func validatePreviewedResolution(
        fileID: Int64,
        strategy: ICloudConflictResolutionStrategy,
        report: ICloudConflictResolveReportSnapshot
    ) async -> Bool {
        let result = ICloudConflictResolutionResult(report: report)
        do {
            try validateICloudConflictResolution(result, fileID: fileID)
            return true
        } catch {
            let mapping = await mapCoreError(error)
            resolutionState = .failed(fileID: fileID, strategy: strategy, mapping)
            return false
        }
    }

    func recordICloudConflictResolutionFailure(
        fileID: Int64,
        strategy: ICloudConflictResolutionStrategy,
        mapping: CoreErrorMappingSnapshot
    ) {
        resolutionState = .failed(fileID: fileID, strategy: strategy, mapping)
    }

    func versions(for file: FileEntrySnapshot?) -> (original: String?, conflictedCopy: String?) {
        (
            ICloudConflictVersionSnapshot.originalCandidate(repoPath: repoPath, file: file).path,
            ICloudConflictVersionSnapshot.conflictedCandidate(repoPath: repoPath, file: file).path
        )
    }

    func completeResolution() {
        resolutionState = .idle
    }

    private func validateICloudConflictResolution(
        _ result: ICloudConflictResolutionResult,
        fileID: Int64
    ) throws {
        guard result.didClearConflictState else {
            throw AppSemanticError.internalFailure(
                rawContext: "iCloud conflict \(fileID) did not clear conflict state"
            )
        }
        guard result.didWriteChangeLog else {
            throw AppSemanticError.internalFailure(
                rawContext: "iCloud conflict \(fileID) did not write change_log"
            )
        }
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
