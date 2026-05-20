import Foundation

struct MultiSelectionDetailRefreshResult: Equatable {
    var files: [FileEntrySnapshot]
    var errorMapping: CoreErrorMappingSnapshot?
}

struct BatchMutationReportPresentation: Equatable {
    let addedSummaryText: String
    let skippedSummaryText: String
    let failedSummaryText: String

    init(report: BatchMutationReportSnapshot) {
        let added = BatchMutationReportSummary(status: .added, relationCount: report.addedCount, report: report)
        let skipped = BatchMutationReportSummary(
            status: .alreadyHadTag,
            relationCount: report.skippedCount,
            report: report
        )
        let failed = BatchMutationReportSummary(status: .failed, relationCount: report.failedCount, report: report)
        addedSummaryText = added.addedText
        skippedSummaryText = skipped.skippedText
        failedSummaryText = failed.failedText
    }
}

private struct BatchMutationReportSummary {
    var status: BatchMutationStatusSnapshot
    var relationCount: Int64
    var report: BatchMutationReportSnapshot

    var addedText: String {
        guard fileCount > 0 else { return relationOnlyText(action: "added", emptyText: "Added to 0 files") }
        return "Added to \(Self.countText(fileCount, singular: "file", plural: "files"))\(relationSuffix)"
    }

    var skippedText: String {
        guard fileCount > 0 else {
            return relationOnlyText(action: "already existed", emptyText: "0 files already had these tags")
        }
        return "\(Self.countText(fileCount, singular: "file", plural: "files")) already had these tags\(relationSuffix)"
    }

    var failedText: String {
        guard fileCount > 0 else { return relationOnlyText(action: "failed", emptyText: "0 failed") }
        return "\(Self.countText(fileCount, singular: "file", plural: "files")) failed\(relationSuffix)"
    }

    private var fileCount: Int64 {
        Int64(Set(report.itemResults.filter { $0.status == status }.map(\.fileID)).count)
    }

    private var relationSuffix: String {
        guard relationCount > 0, relationCount != fileCount else { return "" }
        return " (\(Self.countText(relationCount, singular: "tag relation", plural: "tag relations")))"
    }

    private func relationOnlyText(action: String, emptyText: String) -> String {
        guard relationCount > 0 else { return emptyText }
        return "\(Self.countText(relationCount, singular: "tag relation", plural: "tag relations")) \(action)"
    }

    private static func countText(_ count: Int64, singular: String, plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }
}

struct MultiSelectionDetailRefreshRequest {
    var ids: Set<Int64>
    var repoPath: String
    var currentFiles: [FileEntrySnapshot]
    var detailer: any CoreFileDetailing
    var errorMapper: any CoreErrorMapping
}

enum MultiSelectionDetailLoader {
    static func refresh(
        request: MultiSelectionDetailRefreshRequest,
        shouldContinue: @escaping @MainActor () -> Bool
    ) async -> MultiSelectionDetailRefreshResult? {
        var refreshedFiles: [FileEntrySnapshot] = []
        var firstFailure: CoreErrorMappingSnapshot?

        for id in request.ids.sorted() {
            do {
                let loadedFile = try await request.detailer.getFile(repoPath: request.repoPath, fileID: id)
                guard await shouldContinue() else { return nil }
                if request.ids.contains(loadedFile.id) {
                    refreshedFiles.append(loadedFile)
                }
            } catch {
                let mappedError = await mapCoreError(error, errorMapper: request.errorMapper)
                guard await shouldContinue() else { return nil }
                firstFailure = firstFailure ?? mappedError
            }
        }

        return MultiSelectionDetailRefreshResult(
            files: mergedFiles(replacing: request.currentFiles, with: refreshedFiles),
            errorMapping: firstFailure
        )
    }

    private static func mergedFiles(
        replacing currentFiles: [FileEntrySnapshot],
        with refreshedFiles: [FileEntrySnapshot]
    ) -> [FileEntrySnapshot] {
        var refreshedByID = Dictionary(uniqueKeysWithValues: refreshedFiles.map { ($0.id, $0) })
        let existingFiles = currentFiles.map { file in
            refreshedByID.removeValue(forKey: file.id) ?? file
        }
        return existingFiles + refreshedByID.values.sorted { $0.currentName < $1.currentName }
    }

    private static func mapCoreError(
        _ error: Error,
        errorMapper: any CoreErrorMapping
    ) async -> CoreErrorMappingSnapshot {
        if let coreError = error as? CoreError {
            return await errorMapper.mapCoreError(coreError)
        }
        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
    }
}

extension MainFileListModel {
    var currentCategoryDisplayName: String {
        guard let currentCategory, !currentCategory.isEmpty else { return "files" }
        return currentCategory
    }

    func cachedFile(id: Int64) -> FileEntrySnapshot? {
        files.first { $0.id == id }
    }

    func selectedFileIDForExternalRemoval(path: String) -> Int64? {
        if let selectedFileDetail, selectedFileDetail.path == path {
            return selectedFileDetail.id
        }
        return files.first { $0.path == path }?.id
    }

    func missingDetailSnapshotIfNeeded(_ error: Error, fileID: Int64) -> FileEntrySnapshot? {
        guard case let .FileNotFound(path) = error as? CoreError else { return nil }
        return missingSnapshot(fileID: fileID, fallbackPath: path)
    }

    func missingSnapshot(fileID: Int64, fallbackPath: String) -> FileEntrySnapshot? {
        var snapshot = selectedFileDetail ??
            files.first { $0.id == fileID } ??
            cachedFile(id: fileID)
        snapshot?.availability = .missing
        if snapshot == nil, fallbackPath == "\(fileID)" || fallbackPath.isEmpty {
            return nil
        }
        return snapshot
    }

    func mapCoreError(_ error: Error) async -> CoreErrorMappingSnapshot {
        if let coreError = error as? CoreError {
            return await errorMapper.mapCoreError(coreError)
        }
        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
    }

    func validateExternalSyncResult(
        _ result: SyncResultSnapshot,
        event: MainExternalCreatedFileEvent
    ) throws {
        guard result.errors.isEmpty else {
            throw CoreError.Internal(
                message: """
                \(event.kind.displayName) event \(event.fsEventID) returned sync errors: \(result.errors
                    .joined(separator: "; "))
                """
            )
        }
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
