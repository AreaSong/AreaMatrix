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

extension MainFileListModel {
    var aiTagBatchSuggestionActions: AITagBatchSuggestionActions {
        AITagBatchSuggestionActions(
            load: { [weak self] files in Task { await self?.loadBatchAITagSuggestions(files: files) } },
            retry: { [weak self] in Task { await self?.retryBatchAITagSuggestions() } },
            toggle: { [weak self] fileID, suggestionID in
                self?.toggleBatchAITagSuggestion(fileID: fileID, suggestionID: suggestionID)
            },
            startEditing: { [weak self] fileID, suggestionID in
                self?.startEditingBatchAITagSuggestion(fileID: fileID, suggestionID: suggestionID)
            },
            cancelEditing: { [weak self] fileID in
                self?.cancelEditingBatchAITagSuggestion(fileID: fileID)
            },
            editDisplayName: { [weak self] fileID, suggestionID, displayName in
                self?.updateBatchAITagSuggestionDisplayName(
                    fileID: fileID,
                    suggestionID: suggestionID,
                    displayName: displayName
                )
            },
            editSlug: { [weak self] fileID, suggestionID, slug in
                self?.updateBatchAITagSuggestionSlug(fileID: fileID, suggestionID: suggestionID, slug: slug)
            },
            regenerateSlug: { [weak self] fileID, suggestionID in
                self?.regenerateBatchAITagSuggestionSlug(fileID: fileID, suggestionID: suggestionID)
            },
            selectHighConfidence: { [weak self] in self?.selectHighConfidenceBatchAITagSuggestions() },
            clearSelection: { [weak self] in self?.clearBatchAITagSuggestions() },
            confirm: { [weak self] in self?.confirmBatchAITagSuggestions() },
            cancelConfirmation: { [weak self] in self?.cancelBatchAITagSuggestionConfirmation() },
            apply: { [weak self] in Task { await self?.applyBatchAITagSuggestions() } },
            cancel: { [weak self] in self?.cancelBatchAITagSuggestions() }
        )
    }

    func loadBatchAITagSuggestions(files: [FileEntrySnapshot]) async {
        let selectedIDs = selection.multipleFileIDs
        let selectedFiles = files.filter { selectedIDs.contains($0.id) }
        guard selectedFiles.count > 1 else { return }

        aiTagBatchSuggestionState = .loading(AITagBatchSuggestionAction.initialReview(files: selectedFiles, reports: [:]))
        let review = await loadBatchAITagSuggestionReports(files: selectedFiles, selectedIDs: selectedIDs)
        guard selection.multipleFileIDs == selectedIDs else { return }
        aiTagBatchSuggestionState = .reviewing(review)
    }

    func retryBatchAITagSuggestions() async {
        guard let files = aiTagBatchSuggestionState.review?.files, !files.isEmpty else { return }
        await loadBatchAITagSuggestions(files: files)
    }

    func toggleBatchAITagSuggestion(fileID: Int64, suggestionID: String) {
        aiTagBatchSuggestionState = AITagBatchSuggestionAction.toggling(
            fileID: fileID,
            suggestionID: suggestionID,
            in: aiTagBatchSuggestionState
        )
    }

    func selectHighConfidenceBatchAITagSuggestions() {
        aiTagBatchSuggestionState = AITagBatchSuggestionAction.selectingHighConfidence(in: aiTagBatchSuggestionState)
    }

    func startEditingBatchAITagSuggestion(fileID: Int64, suggestionID: String) {
        aiTagBatchSuggestionState = AITagBatchSuggestionAction.startingEdit(
            fileID: fileID,
            suggestionID: suggestionID,
            in: aiTagBatchSuggestionState,
            disabledReason: writeActionDisabledReason(fileID: fileID)?.rawValue
        )
    }

    func cancelEditingBatchAITagSuggestion(fileID: Int64) {
        aiTagBatchSuggestionState = AITagBatchSuggestionAction.cancelingEdit(
            fileID: fileID,
            in: aiTagBatchSuggestionState
        )
    }

    func updateBatchAITagSuggestionDisplayName(fileID: Int64, suggestionID: String, displayName: String) {
        aiTagBatchSuggestionState = AITagBatchSuggestionAction.updatingDisplayName(
            fileID: fileID,
            suggestionID: suggestionID,
            displayName: displayName,
            in: aiTagBatchSuggestionState,
            disabledReason: writeActionDisabledReason(fileID: fileID)?.rawValue
        )
    }

    func updateBatchAITagSuggestionSlug(fileID: Int64, suggestionID: String, slug: String) {
        aiTagBatchSuggestionState = AITagBatchSuggestionAction.updatingSlug(
            fileID: fileID,
            suggestionID: suggestionID,
            slug: slug,
            in: aiTagBatchSuggestionState,
            disabledReason: writeActionDisabledReason(fileID: fileID)?.rawValue
        )
    }

    func regenerateBatchAITagSuggestionSlug(fileID: Int64, suggestionID: String) {
        aiTagBatchSuggestionState = AITagBatchSuggestionAction.regeneratingSlug(
            fileID: fileID,
            suggestionID: suggestionID,
            in: aiTagBatchSuggestionState,
            disabledReason: writeActionDisabledReason(fileID: fileID)?.rawValue
        )
    }

    func clearBatchAITagSuggestions() {
        aiTagBatchSuggestionState = AITagBatchSuggestionAction.clearingSelection(in: aiTagBatchSuggestionState)
    }

    func confirmBatchAITagSuggestions() {
        guard let review = aiTagBatchSuggestionState.review, review.canApply else { return }
        aiTagBatchSuggestionState = .confirming(review)
    }

    func cancelBatchAITagSuggestionConfirmation() {
        guard case let .confirming(review) = aiTagBatchSuggestionState else { return }
        aiTagBatchSuggestionState = .reviewing(review)
    }

    func applyBatchAITagSuggestions() async {
        guard case var .confirming(review) = aiTagBatchSuggestionState else { return }
        let selectedIDs = selection.multipleFileIDs
        guard selectedIDs == Set(review.files.map(\.id)), review.canApply else { return }

        aiTagBatchSuggestionState = .applying(review)
        review.applyReports = [:]
        review.applyFailures = [:]
        for file in review.files {
            let result = await applyBatchAITagSuggestions(fileID: file.id, review: review)
            if let applyReport = result.applyReport {
                review.applyReports[file.id] = applyReport
                review.selectedIDsByFileID[file.id] = failedSuggestionIDs(in: applyReport)
                review.editSessionsByFileID[file.id] = nil
            }
            if let failure = result.failure {
                review.applyFailures[file.id] = failure
            }
        }
        guard selection.multipleFileIDs == selectedIDs else { return }
        aiTagBatchSuggestionState = .applied(review)
        await loadSelectedFileChangeLog()
    }

    func cancelBatchAITagSuggestions() {
        aiTagBatchSuggestionState = .idle
    }

    private func loadBatchAITagSuggestionReports(
        files: [FileEntrySnapshot],
        selectedIDs: Set<Int64>
    ) async -> AITagBatchSuggestionReview {
        var reports: [Int64: AiTagSuggestionReport] = [:]
        var failures: [Int64: CoreErrorMappingSnapshot] = [:]
        for file in files {
            do {
                reports[file.id] = try await suggestAITagsWithPrivacyGate(fileID: file.id, file: file, candidateTags: [])
            } catch {
                failures[file.id] = await mapCoreError(error)
            }
            guard selection.multipleFileIDs == selectedIDs else {
                return AITagBatchSuggestionAction.initialReview(files: files, reports: reports, loadFailures: failures)
            }
        }
        return AITagBatchSuggestionAction.initialReview(files: files, reports: reports, loadFailures: failures)
    }

    private func applyBatchAITagSuggestions(
        fileID: Int64,
        review: AITagBatchSuggestionReview
    ) async -> (applyReport: AiTagSuggestionApplyReport?, failure: CoreErrorMappingSnapshot?) {
        guard let report = review.reports[fileID] else { return (nil, nil) }
        let items = review.applyItems(fileID: fileID)
        guard !items.isEmpty, writeActionDisabledReason(fileID: fileID) == nil else { return (nil, nil) }

        do {
            let applyReport = try await aiTagSuggestionStore.applyAITagSuggestions(
                repoPath: repoPath,
                request: ApplyAiTagSuggestionsRequest(
                    fileId: fileID,
                    suggestions: items,
                    callLogId: report.callLogId,
                    privacyRuleId: report.privacyRuleId,
                    confirmed: true
                )
            )
            return (applyReport, nil)
        } catch {
            return (nil, await mapCoreError(error))
        }
    }

    private func failedSuggestionIDs(in report: AiTagSuggestionApplyReport) -> Set<String> {
        Set(report.itemResults.compactMap { $0.status == .failed ? $0.suggestionId : nil })
    }
}
