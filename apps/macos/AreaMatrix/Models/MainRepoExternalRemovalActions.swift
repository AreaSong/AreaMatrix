import Foundation

enum MainRepoExternalRemovalState: Equatable {
    case unavailable
    case idle(relativePath: String)
    case syncing(relativePath: String)
    case synced(SyncResultSnapshot)
    case failed(CoreErrorMappingSnapshot)

    var relativePath: String? {
        switch self {
        case let .idle(path), let .syncing(path):
            path
        case .unavailable, .synced, .failed:
            nil
        }
    }
}

extension OnboardingModel {
    @MainActor
    func confirmMainRepositoryExternalRemoval(repoPath: String) async {
        guard !isRetryingMainRepository else { return }
        guard let relativePath = mainRepoExternalRemoval.relativePath else { return }

        isRetryingMainRepository = true
        mainRepoExternalRemoval = .syncing(relativePath: relativePath)
        mainRepoRecoveryErrorMapping = nil

        do {
            let result = try await externalChangesSyncer.syncExternalRemoved(
                repoPath: repoPath,
                relativePath: relativePath,
                fsEventID: Self.manualExternalRemovalEventID
            )
            mainRepoExternalRemoval = .synced(result)
            isRetryingMainRepository = false
            await retryMainRepositoryFromError(repoPath: repoPath)
        } catch {
            isRetryingMainRepository = false
            let mapping = await openingFailureMapping(for: error)
            mainRepoExternalRemoval = .failed(mapping)
            mainRepoRecoveryErrorMapping = mapping
            routeMainRepositoryError(repoPath: repoPath, mapping: mapping)
        }
    }

    func updateMainRepoExternalRemoval(from error: Error, repoPath: String) async {
        guard let path = Self.removedRelativePath(from: error, repoPath: repoPath) else {
            mainRepoExternalRemoval = .unavailable
            return
        }

        mainRepoExternalRemoval = .idle(relativePath: path)
    }

    private static func removedRelativePath(from error: Error, repoPath: String) -> String? {
        guard case let .FileNotFound(path) = error as? CoreError else { return nil }

        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasSuffix("/") else { return nil }
        if trimmed.hasPrefix("/") {
            let repoURL = URL(fileURLWithPath: repoPath, isDirectory: true).standardizedFileURL
            let fileURL = URL(fileURLWithPath: trimmed).standardizedFileURL
            guard fileURL.path.hasPrefix(repoURL.path + "/") else { return nil }
            return String(fileURL.path.dropFirst(repoURL.path.count + 1))
        }

        guard !trimmed.hasPrefix("../"), !trimmed.contains("/../") else { return nil }
        return trimmed
    }

    private static var manualExternalRemovalEventID: Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}

extension CoreErrorMappingSnapshot {
    static func missingFromExternalChange(fileID: Int64) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .fileNotFound,
            userMessage: "The selected file is missing.",
            severity: .medium,
            suggestedAction: "Refresh the current list or remove the stale index entry.",
            recoverability: .refreshRequired,
            rawContext: "file_id=\(fileID)"
        )
    }
}
