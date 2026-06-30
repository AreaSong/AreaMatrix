import Foundation

extension RepositorySettingsModel {
    func refreshHealth() async {
        var summary = RepositorySettingsHealthSummary(
            databaseStatus: .ok,
            schemaVersion: nil,
            filesIndexed: nil,
            lastOpenedAt: nil,
            lastScanAt: nil,
            watcherStatus: .paused
        )

        do {
            let metadata = try await existingRepositoryMetadataReader.metadata(repoPath: repoPath)
            summary.schemaVersion = metadata.schemaVersion
            summary.lastOpenedAt = metadata.lastOpenedAt
        } catch {
            summary = await applyHealthError(error, summary: summary)
            healthSummary = summary
            return
        }

        do {
            summary.filesIndexed = try await indexedFileCount()
        } catch {
            summary = await applyHealthError(error, summary: summary)
            healthSummary = summary
            return
        }

        do {
            let scanSession = try await scanSessionReader.latestScanSession(repoPath: repoPath)
            if let scanSession {
                summary.lastScanAt = scanSession.finishedAt ?? scanSession.updatedAt
                summary.watcherStatus = scanSession.status == .running ? .running : .paused
            }
        } catch {
            summary = await applyHealthError(error, summary: summary)
        }

        healthSummary = summary
    }

    private func indexedFileCount() async throws -> Int64 {
        guard let fileLister else {
            let opening = try await repositoryOpener.openConfiguredRepository(repoPath: repoPath)
            return opening.tree.totalFileCount
        }

        return try await Self.countIndexedFiles(repoPath: repoPath, fileLister: fileLister)
    }

    private static func countIndexedFiles(
        repoPath: String,
        fileLister: any CoreFileListing
    ) async throws -> Int64 {
        let pageSize: Int64 = 1000
        var offset: Int64 = 0
        var total: Int64 = 0

        while true {
            let files = try await fileLister.listFiles(
                repoPath: repoPath,
                filter: FileFilterSnapshot(
                    category: nil,
                    includeDeleted: false,
                    importedAfter: nil,
                    importedBefore: nil,
                    limit: pageSize,
                    offset: offset
                )
            )
            total += Int64(files.count)
            guard Int64(files.count) == pageSize else {
                return total
            }
            offset += pageSize
        }
    }

    private func applyHealthError(
        _ error: Error,
        summary: RepositorySettingsHealthSummary
    ) async -> RepositorySettingsHealthSummary {
        var updatedSummary = summary
        if let coreError = error as? CoreError {
            let mappingResult = await errorMapper.mapCoreError(coreError)
            let status = databaseStatus(for: mappingResult)
            updatedSummary.databaseStatus = status
            healthError = RepositorySettingsHealthError(
                databaseStatus: status,
                message: mappingResult.userMessage,
                recovery: mappingResult.suggestedAction
            )
        } else {
            updatedSummary.databaseStatus = .needsRecovery
            healthError = RepositorySettingsHealthError(
                databaseStatus: .needsRecovery,
                message: error.localizedDescription,
                recovery: "Retry status after the repository is available."
            )
        }
        return updatedSummary
    }

    private func databaseStatus(for mapping: CoreErrorMappingSnapshot) -> RepositorySettingsDatabaseStatus {
        switch mapping.kind {
        case .permissionDenied:
            .locked
        case .db:
            mapping.recoverability == .retryable ? .locked : .needsRecovery
        case .config, .repoNotInitialized, .internal:
            .needsRecovery
        default:
            mapping.recoverability == .retryable ? .locked : .needsRecovery
        }
    }
}
