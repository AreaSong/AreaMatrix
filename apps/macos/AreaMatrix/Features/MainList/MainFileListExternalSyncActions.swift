import Foundation

private struct MainSelectedExternalRemovalRefresh {
    let event: MainExternalCreatedFileEvent?
    let snapshot: FileEntrySnapshot?
    let loadedFiles: [FileEntrySnapshot]
    let selectedFileID: Int64?
    let selectionGeneration: Int
    let result: SyncResultSnapshot
    let isRetry: Bool
}

extension MainFileListModel {
    func scheduleExternalSyncDrain(
        windows: [MainExternalSyncWindow],
        onWindowCompleted: @escaping @MainActor (MainExternalSyncWindow) -> Void
    ) {
        guard externalSyncDrainTask == nil, let window = windows.first else { return }
        externalSyncDrainTask = Task { [weak self] in
            guard let self else { return }
            let committed = await syncExternalWindow(window)
            externalSyncDrainTask = nil
            if committed { onWindowCompleted(window) }
        }
    }

    func loadSelectedFileChangeLog() async {
        if let selectedFileID = selection.singleFileID { await loadChangeLog(fileID: selectedFileID) }
    }

    func retrySelectedFileChangeLog() async {
        if let selectedFileID = selection.singleFileID { await loadChangeLog(fileID: selectedFileID) }
    }

    @discardableResult
    func syncExternalCreated(_ event: MainExternalCreatedFileEvent) async -> Bool {
        await syncExternalChanges([event])
    }

    @discardableResult
    func syncExternalChanges(_ events: [MainExternalCreatedFileEvent]) async -> Bool {
        guard let cursorWatermark = events.map(\.cursorWatermark).max(),
              let window = MainExternalSyncWindow(
                  repoPath: repoPath,
                  events: events,
                  cursorWatermark: cursorWatermark
              ) else { return events.isEmpty }
        return await syncExternalWindow(window)
    }

    @discardableResult
    func syncExternalWindow(_ window: MainExternalSyncWindow) async -> Bool {
        let normalizedRepoPath = URL(fileURLWithPath: repoPath, isDirectory: true).standardizedFileURL.path
        guard window.repoPath == normalizedRepoPath else { return false }
        let isRetryingWindow = failedExternalSyncWindowID == window.id
        guard let focusEvent = window.events.last else { return await acknowledgeFilteredWindow(window) }

        let selectedFileIDBeforeSync = selection.singleFileID
        let selectionGeneration = detailGeneration
        let detailTargetFileIDBeforeSync = detailTargetFileID(in: window)
        if let detailTargetFileIDBeforeSync {
            detailExternalCreateSyncState = .syncing(fileID: detailTargetFileIDBeforeSync, event: focusEvent)
        } else {
            detailExternalCreateSyncState = .idle
        }
        let result: SyncResultSnapshot
        do {
            result = try await commitExternalWindow(
                window,
                focusEvent: focusEvent,
                isRetry: isRetryingWindow
            )
        } catch {
            let mappedError = await mapCoreError(error)
            if let detailTargetFileIDBeforeSync,
               canApplyExternalSelectionUpdate(
                   fileID: detailTargetFileIDBeforeSync,
                   generation: selectionGeneration
               ) {
                detailExternalCreateSyncState = .failed(
                    fileID: detailTargetFileIDBeforeSync,
                    event: focusEvent,
                    mappedError
                )
            }
            markExternalSyncFailure(window, mapping: mappedError)
            return false
        }

        await refreshPresentationAfterCommittedWindow(
            window,
            result: result,
            selectedFileID: selectedFileIDBeforeSync,
            selectionGeneration: selectionGeneration,
            isRetry: isRetryingWindow
        )
        clearExternalSyncFailure()
        return true
    }

    private func commitExternalWindow(
        _ window: MainExternalSyncWindow,
        focusEvent: MainExternalCreatedFileEvent,
        isRetry: Bool
    ) async throws -> SyncResultSnapshot {
        try await repositoryWriteCoordinator.withWriteAccess(repoPath: repoPath) {
            let result = try await self.externalChangesSyncer.syncExternalChanges(
                repoPath: self.repoPath,
                events: window.events
            )
            try self.validateExternalSyncResult(result, event: focusEvent)
            try self.validateSelectedExternalRemoval(result, window: window, allowsReplayNoOp: isRetry)
            if let syncedEventID = window.events.map(\.fsEventID).max(),
               window.cursorWatermark > syncedEventID {
                try await self.externalChangesSyncer.setFSEventCursor(
                    repoPath: self.repoPath,
                    lastEventID: window.cursorWatermark
                )
            }
            return result
        }
    }

    private func acknowledgeFilteredWindow(_ window: MainExternalSyncWindow) async -> Bool {
        do {
            try await repositoryWriteCoordinator.withWriteAccess(repoPath: repoPath) {
                try await self.externalChangesSyncer.setFSEventCursor(
                    repoPath: self.repoPath,
                    lastEventID: window.cursorWatermark
                )
            }
            clearExternalSyncFailure()
            return true
        } catch {
            let mappedError = await mapCoreError(error)
            markExternalSyncFailure(window, mapping: mappedError)
            return false
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

    private func refreshChangeLogForSyncedFile(_ fileID: Int64?) async {
        guard let fileID else { return }
        await loadChangeLog(fileID: fileID)
    }

    private func refreshPresentationAfterCommittedWindow(
        _ window: MainExternalSyncWindow,
        result: SyncResultSnapshot,
        selectedFileID: Int64?,
        selectionGeneration: Int,
        isRetry: Bool
    ) async {
        guard let focusEvent = window.events.last else { return }
        if result.hasNoDetectedChanges, !isRetry {
            setExternalSyncSucceeded(fileID: selectedFileID, event: focusEvent, result: result)
            return
        }

        let selectedRemoval = window.events.reversed().first { event in
            guard event.kind == .removed, let selectedFileID else { return false }
            return selectedFileIDForExternalRemoval(path: event.relativePath) == selectedFileID
        }
        let removedSnapshot = selectedRemoval.flatMap { event in
            selectedFileID.flatMap { missingSnapshot(fileID: $0, fallbackPath: event.relativePath) }
        }

        do {
            guard let loadedFiles = try await reloadFilesForExternalSync() else {
                setExternalSyncSucceeded(fileID: selectedFileID, event: focusEvent, result: result)
                return
            }
            if await restoreSelectedExternalRename(
                in: window,
                files: loadedFiles,
                selectedID: selectedFileID,
                selectionGeneration: selectionGeneration,
                result: result
            ) {
                return
            }
            let removalRefresh = MainSelectedExternalRemovalRefresh(
                event: selectedRemoval,
                snapshot: removedSnapshot,
                loadedFiles: loadedFiles,
                selectedFileID: selectedFileID,
                selectionGeneration: selectionGeneration,
                result: result,
                isRetry: isRetry
            )
            if await applySelectedExternalRemoval(removalRefresh) {
                return
            }
            await preserveSelectionAfterExternalSync(
                in: window,
                files: loadedFiles,
                selectedFileID: selectedFileID,
                selectionGeneration: selectionGeneration,
                result: result
            )
        } catch {
            errorMapping = await mapCoreError(error)
            setExternalSyncSucceeded(fileID: selectedFileID, event: focusEvent, result: result)
        }
    }

    private func applySelectedExternalRemoval(_ refresh: MainSelectedExternalRemovalRefresh) async -> Bool {
        guard let event = refresh.event,
              let selectedFileID = refresh.selectedFileID,
              refresh.result.detectedDeletes > 0 || refresh.isRetry,
              canApplyExternalSelectionUpdate(
                  fileID: selectedFileID,
                  generation: refresh.selectionGeneration
              ) else {
            return false
        }
        files = refresh.loadedFiles.filter { $0.id != selectedFileID }
        selection = .single(selectedFileID)
        selectedFileDetail = refresh.snapshot
        selectedFileNoteWriteBlock = refresh.snapshot.flatMap { noteWriteBlock(for: $0) }
        detailErrorMapping = CoreErrorMappingSnapshot.missingFromExternalChange(fileID: selectedFileID)
        isDetailLoading = false; detailTagEditorState = .notLoaded; detailTagSuggestionState = .idle
        statusBanner = .removedSelectedFile(fileID: selectedFileID)
        detailExternalCreateSyncState = .synced(fileID: selectedFileID, event: event, refresh.result)
        await refreshChangeLogForSyncedFile(selectedFileID)
        return true
    }

    private func preserveSelectionAfterExternalSync(
        in window: MainExternalSyncWindow,
        files loadedFiles: [FileEntrySnapshot],
        selectedFileID: Int64?,
        selectionGeneration: Int,
        result: SyncResultSnapshot
    ) async {
        guard let focusEvent = window.events.last else { return }
        guard let selectedFileID,
              canApplyExternalSelectionUpdate(fileID: selectedFileID, generation: selectionGeneration),
              let selectedFile = loadedFiles.first(where: { $0.id == selectedFileID }) else {
            setExternalSyncSucceeded(fileID: selectedFileID, event: focusEvent, result: result)
            return
        }

        selectedFileDetail = selectedFile
        selectedFileNoteWriteBlock = noteWriteBlock(for: selectedFile)
        detailErrorMapping = nil
        guard let selectedEvent = window.events.reversed().first(where: { event in
            event.kind != .removed && event.relativePath == selectedFile.path
        }) else {
            detailExternalCreateSyncState = .idle
            return
        }

        isDetailLoading = true
        let expectedDetailGeneration = detailGeneration + 1
        await loadDetail(id: selectedFileID)
        guard detailGeneration == expectedDetailGeneration,
              selection.singleFileID == selectedFileID else { return }
        detailExternalCreateSyncState = .synced(fileID: selectedFileID, event: selectedEvent, result)
        await refreshChangeLogForSyncedFile(selectedFileID)
    }

    private func restoreSelectedExternalRename(
        in window: MainExternalSyncWindow,
        files loadedFiles: [FileEntrySnapshot],
        selectedID selectedFileID: Int64?,
        selectionGeneration: Int,
        result: SyncResultSnapshot
    ) async -> Bool {
        let renamedEvents = window.events.filter { $0.kind == .renamed }
        guard let selectedFileID,
              !renamedEvents.isEmpty,
              canApplyExternalSelectionUpdate(fileID: selectedFileID, generation: selectionGeneration) else {
            return false
        }
        if let selectedFile = loadedFiles.first(where: { $0.id == selectedFileID }),
           !renamedEvents.contains(where: { $0.relativePath == selectedFile.path }) {
            return false
        }

        isDetailLoading = true
        let expectedDetailGeneration = detailGeneration + 1
        await loadDetail(id: selectedFileID)
        guard detailGeneration == expectedDetailGeneration,
              selection.singleFileID == selectedFileID else { return true }
        if let movedFile = selectedFileDetail,
           detailErrorMapping == nil,
           let renamedEvent = renamedEvents.last(where: { $0.relativePath == movedFile.path }) {
            setPendingExternalSelectionUpdate(.moved(movedFile))
            statusBanner = .renamedPreservedSelection(fileID: selectedFileID)
            detailExternalCreateSyncState = .synced(fileID: selectedFileID, event: renamedEvent, result)
            await refreshChangeLogForSyncedFile(selectedFileID)
            return true
        }
        return false
    }

    private func validateSelectedExternalRemoval(
        _ result: SyncResultSnapshot,
        window: MainExternalSyncWindow,
        allowsReplayNoOp: Bool
    ) throws {
        guard !allowsReplayNoOp,
              window.events.count == 1,
              let event = window.events.first,
              event.kind == .removed,
              selectedFileIDForExternalRemoval(path: event.relativePath) != nil,
              result.detectedDeletes == 0 else { return }
        throw MainExternalSyncRefreshValidationError(
            rawContext: "removed event \(event.fsEventID) did not report a detected delete: \(event.relativePath)"
        )
    }

    private func markExternalSyncFailure(
        _ window: MainExternalSyncWindow,
        mapping: CoreErrorMappingSnapshot
    ) {
        failedExternalSyncWindowID = window.id
        failedExternalSyncRelativePath = placeholderRelativePath(in: window, mapping: mapping)
        setExternalSyncErrorMapping(mapping)
    }

    private func clearExternalSyncFailure() {
        failedExternalSyncWindowID = nil
        failedExternalSyncRelativePath = nil
        clearExternalSyncRecoveryMessage()
        setExternalSyncErrorMapping(nil)
    }

    private func placeholderRelativePath(
        in window: MainExternalSyncWindow,
        mapping: CoreErrorMappingSnapshot
    ) -> String? {
        guard mapping.kind == .iCloudPlaceholder else { return nil }
        return window.events.first { event in
            mapping.rawContext == event.relativePath || mapping.rawContext.hasSuffix("/\(event.relativePath)")
        }?.relativePath
    }

    private func reloadFilesForExternalSync() async throws -> [FileEntrySnapshot]? {
        guard !searchState.isActive else { return nil }
        loadGeneration += 1
        let generation = loadGeneration
        let category = currentCategory
        let reloadLimit = max(Self.fileListPageSize, nextFilePageOffset)
        var filter = FileFilterSnapshot.currentCategory(category)
        filter.limit = reloadLimit
        filter.offset = 0
        isLoading = true
        do {
            let loadedFiles = try await fileLister.listFiles(
                repoPath: repoPath,
                filter: filter
            )
            guard canApplyExternalListReload(generation: generation, category: category) else { return nil }
            files = loadedFiles
            nextFilePageOffset = Int64(loadedFiles.count); hasMore = loadedFiles.count == Int(reloadLimit)
            isLoadingMore = false
            loadMoreErrorMapping = nil
            errorMapping = nil
            isLoading = false
            return loadedFiles
        } catch {
            guard canApplyExternalListReload(generation: generation, category: category) else { return nil }
            let mapping = await mapCoreError(error)
            guard canApplyExternalListReload(generation: generation, category: category) else { return nil }
            errorMapping = mapping
            isLoading = false
            throw error
        }
    }

    private func canApplyExternalListReload(generation: Int, category: String?) -> Bool {
        generation == loadGeneration && currentCategory == category && !searchState.isActive
    }

    private func canApplyExternalSelectionUpdate(fileID: Int64, generation: Int) -> Bool {
        generation == detailGeneration && selection.singleFileID == fileID
    }

    private func setExternalSyncSucceeded(
        fileID: Int64?,
        event: MainExternalCreatedFileEvent,
        result: SyncResultSnapshot
    ) {
        guard let fileID,
              selection.singleFileID == fileID,
              eventTargetsSelectedDetail(event, fileID: fileID) else {
            detailExternalCreateSyncState = .idle
            return
        }
        detailExternalCreateSyncState = .synced(fileID: fileID, event: event, result)
    }

    private func detailTargetFileID(in window: MainExternalSyncWindow) -> Int64? {
        guard let fileID = selection.singleFileID,
              window.events.contains(where: { eventTargetsSelectedDetail($0, fileID: fileID) }) else {
            return nil
        }
        return fileID
    }

    private func eventTargetsSelectedDetail(
        _ event: MainExternalCreatedFileEvent,
        fileID: Int64
    ) -> Bool {
        if event.kind == .removed {
            return selectedFileIDForExternalRemoval(path: event.relativePath) == fileID
        }
        let selectedPath = selectedFileDetail?.id == fileID ? selectedFileDetail?.path : cachedFile(id: fileID)?.path
        return selectedPath == event.relativePath
    }
}
