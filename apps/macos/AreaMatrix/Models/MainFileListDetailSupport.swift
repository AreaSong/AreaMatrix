import Foundation

struct MultiSelectionDetailRefreshResult: Equatable, Sendable {
    var files: [FileEntrySnapshot]
    var errorMapping: CoreErrorMappingSnapshot?
}

enum MultiSelectionDetailLoader {
    static func refresh(
        ids: Set<Int64>,
        repoPath: String,
        currentFiles: [FileEntrySnapshot],
        detailer: any CoreFileDetailing,
        errorMapper: any CoreErrorMapping,
        shouldContinue: @escaping @MainActor () -> Bool
    ) async -> MultiSelectionDetailRefreshResult? {
        var refreshedFiles: [FileEntrySnapshot] = []
        var firstFailure: CoreErrorMappingSnapshot?

        for id in ids.sorted() {
            do {
                let loadedFile = try await detailer.getFile(repoPath: repoPath, fileID: id)
                guard await shouldContinue() else { return nil }
                if ids.contains(loadedFile.id) {
                    refreshedFiles.append(loadedFile)
                }
            } catch {
                let mappedError = await mapCoreError(error, errorMapper: errorMapper)
                guard await shouldContinue() else { return nil }
                firstFailure = firstFailure ?? mappedError
            }
        }

        return MultiSelectionDetailRefreshResult(
            files: mergedFiles(replacing: currentFiles, with: refreshedFiles),
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
        guard case .FileNotFound(let path) = error as? CoreError else { return nil }
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
