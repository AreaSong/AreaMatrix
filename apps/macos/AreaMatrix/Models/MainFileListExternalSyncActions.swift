import Foundation

extension MainFileListModel {
    func loadSelectedFileChangeLog() async {
        if let selectedFileID = selection.singleFileID { await loadChangeLog(fileID: selectedFileID) }
    }

    func retrySelectedFileChangeLog() async {
        if let selectedFileID = selection.singleFileID { await loadChangeLog(fileID: selectedFileID) }
    }

    func syncExternalCreated(_ event: MainExternalCreatedFileEvent) async {
        detailExternalCreateSyncState = .syncing(event: event)
        do {
            let result = try await syncExternalChange(event)
            try validateExternalSyncResult(result, event: event)
            let fileID = try await refreshAfterExternalSync(event, result: result)
            detailExternalCreateSyncState = .synced(event: event, fileID: fileID, result)
            await openChangeLogForSyncedFile(fileID)
        } catch {
            let mappedError = await mapCoreError(error)
            detailExternalCreateSyncState = .failed(event: event, mappedError)
        }
    }

    func loadChangeLog(fileID: Int64) async {
        detailLogGeneration += 1
        let generation = detailLogGeneration

        detailLogState = .loading(fileID: fileID)
        detailLogDiagnosticsState = .idle
        do {
            let entries = try await changeLogLister.listChanges(
                repoPath: repoPath,
                filter: .detailLog(fileID: fileID)
            )
            guard generation == detailLogGeneration, selection.singleFileID == fileID else { return }
            detailLogState = .loaded(fileID: fileID, entries: entries)
        } catch {
            let mappedError = await mapCoreError(error)
            guard generation == detailLogGeneration, selection.singleFileID == fileID else { return }
            detailLogState = .failed(fileID: fileID, mappedError)
        }
    }

    private func openChangeLogForSyncedFile(_ fileID: Int64?) async {
        guard let fileID else { return }
        await loadChangeLog(fileID: fileID)
        if case let .loaded(loadedFileID, _) = detailLogState, loadedFileID == fileID {
            detailTabRequest = .automatic(.log)
        }
    }

    private func syncExternalChange(_ event: MainExternalCreatedFileEvent) async throws -> SyncResultSnapshot {
        switch event.kind {
        case .created:
            try await externalChangesSyncer.syncExternalCreated(
                repoPath: repoPath,
                relativePath: event.relativePath,
                fsEventID: event.fsEventID
            )
        case .renamed:
            try await externalChangesSyncer.syncExternalRenamed(
                repoPath: repoPath,
                relativePath: event.relativePath,
                fsEventID: event.fsEventID
            )
        case .removed:
            try await externalChangesSyncer.syncExternalRemoved(
                repoPath: repoPath,
                relativePath: event.relativePath,
                fsEventID: event.fsEventID
            )
        }
    }

    private func refreshAfterExternalSync(
        _ event: MainExternalCreatedFileEvent,
        result: SyncResultSnapshot
    ) async throws -> Int64? {
        if event.kind == .removed {
            return try await refreshAfterExternalRemovedSync(event, result: result)
        }

        let loadedFiles = try await reloadFilesForExternalSync()
        guard let file = loadedFiles.first(where: { $0.path == event.relativePath }) else {
            throw CoreError.Internal(
                message: "\(event.kind.displayName) file was not visible after sync: \(event.relativePath)"
            )
        }

        selection = .single(file.id)
        selectedFileDetail = file
        selectedFileNoteWriteBlock = noteWriteBlock(for: file)
        detailErrorMapping = nil
        isDetailLoading = true
        await loadDetail(id: file.id)
        guard selectedFileDetail?.id == file.id, detailErrorMapping == nil else {
            throw CoreError.Internal(
                message: "\(event.kind.displayName) file detail was not visible after sync: \(event.relativePath)"
            )
        }
        if event.kind == .renamed { statusBanner = .renamedPreservedSelection(fileID: file.id) }
        return file.id
    }

    private func refreshAfterExternalRemovedSync(
        _ event: MainExternalCreatedFileEvent,
        result: SyncResultSnapshot
    ) async throws -> Int64? {
        let removedFileID = selectedFileIDForExternalRemoval(path: event.relativePath)
        let removedSnapshot = removedFileID.flatMap { missingSnapshot(fileID: $0, fallbackPath: event.relativePath) }
        let loadedFiles = try await reloadFilesForExternalSync()
        guard let removedFileID else { return nil }
        guard result.detectedDeletes > 0 else {
            throw CoreError.Internal(
                message: "removed event \(event.fsEventID) did not report a detected delete: \(event.relativePath)"
            )
        }

        files = loadedFiles.filter { $0.id != removedFileID }
        selection = .single(removedFileID)
        selectedFileDetail = removedSnapshot
        selectedFileNoteWriteBlock = removedSnapshot.flatMap { noteWriteBlock(for: $0) }
        detailErrorMapping = CoreErrorMappingSnapshot.missingFromExternalChange(fileID: removedFileID)
        isDetailLoading = false
        detailTagEditorState = .notLoaded
        detailTagSuggestionState = .idle
        statusBanner = .removedSelectedFile(fileID: removedFileID)
        return removedFileID
    }

    private func reloadFilesForExternalSync() async throws -> [FileEntrySnapshot] {
        isLoading = true
        do {
            let loadedFiles = try await fileLister.listFiles(
                repoPath: repoPath,
                filter: .currentCategory(currentCategory)
            )
            files = loadedFiles
            errorMapping = nil
            isLoading = false
            return loadedFiles
        } catch {
            errorMapping = await mapCoreError(error)
            isLoading = false
            throw error
        }
    }
}
