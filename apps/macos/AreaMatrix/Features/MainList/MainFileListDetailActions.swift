import Foundation

extension MainFileListModel {
    func selectFiles(_ ids: Set<Int64>) async {
        if ids.isEmpty { clearDetail(); return }

        guard ids.count == 1, let id = ids.first else {
            selection = .multiple(ids)
            selectedFileDetail = nil; selectedFileNoteWriteBlock = nil; detailErrorMapping = nil
            missingFileRelinkState = .idle
            detailTagModel.editorState = .notLoaded
            detailTagModel.suggestionState = .idle
            isDetailLoading = true
            resetDetailLog()
            await loadMultiSelectionDetails(ids: ids)
            return
        }

        await selectFile(id: id)
    }

    func selectFile(id: Int64?) async {
        guard let id else { clearDetail(); return }

        selection = .single(id); selectedFileDetail = cachedFile(id: id)
        missingFileRelinkState = .idle
        selectedFileNoteWriteBlock = selectedFileDetail.flatMap { noteWriteBlock(for: $0) }
        detailErrorMapping = nil
        isDetailLoading = true
        resetDetailLog()
        await loadDetail(id: id)
    }

    func retrySelectedFileDetail() async {
        if selection.isMultiple {
            detailErrorMapping = nil
            isDetailLoading = true
            await loadMultiSelectionDetails(ids: selection.multipleFileIDs)
            return
        }

        guard let selectedFileID = selection.singleFileID else { return }

        selectedFileDetail = selectedFileDetail ?? cachedFile(id: selectedFileID)
        selectedFileNoteWriteBlock = selectedFileDetail.flatMap { noteWriteBlock(for: $0) }
        detailErrorMapping = nil
        isDetailLoading = true
        await loadDetail(id: selectedFileID)
    }

    func loadDetail(id: Int64) async {
        detailGeneration += 1
        let generation = detailGeneration

        do {
            let loadedFile = try await fileDetailer.getFile(repoPath: repoPath, fileID: id)
            guard generation == detailGeneration, selection.singleFileID == id else { return }
            selectedFileDetail = loadedFile
            selectedFileNoteWriteBlock = noteWriteBlock(for: loadedFile)
            files = files.map { $0.id == loadedFile.id ? loadedFile : $0 }
            detailErrorMapping = nil
            isDetailLoading = false
            detailTagModel.editorState = .notLoaded
            detailTagModel.suggestionState = .idle
        } catch {
            let mappedError = await mapCoreError(error)
            guard generation == detailGeneration, selection.singleFileID == id else { return }
            selectedFileDetail = missingDetailSnapshotIfNeeded(error, fileID: id) ??
                selectedFileDetail ??
                cachedFile(id: id)
            selectedFileNoteWriteBlock = selectedFileDetail.flatMap { noteWriteBlock(for: $0) }
            detailErrorMapping = mappedError
            isDetailLoading = false
        }
    }

    private func loadMultiSelectionDetails(ids: Set<Int64>) async {
        detailGeneration += 1
        let generation = detailGeneration
        guard let result = await MultiSelectionDetailLoader.refresh(
            request: MultiSelectionDetailRefreshRequest(
                ids: ids,
                repoPath: repoPath,
                currentFiles: files,
                detailer: fileDetailer,
                errorMapper: errorMapper
            ),
            shouldContinue: { [weak self] in
                self?.canApplyMultiSelectionDetailResult(generation: generation, ids: ids) == true
            }
        ) else { return }

        guard canApplyMultiSelectionDetailResult(generation: generation, ids: ids) else { return }
        files = result.files
        selectedFileDetail = nil
        selectedFileNoteWriteBlock = nil
        detailErrorMapping = result.errorMapping
        isDetailLoading = false
    }

    func clearDetail() {
        detailGeneration += 1
        selection = .none
        selectedFileDetail = nil; selectedFileNoteWriteBlock = nil; detailErrorMapping = nil
        missingFileRelinkState = .idle
        detailTagModel.editorState = .notLoaded
        detailTagModel.suggestionState = .idle
        detailTagModel.clearTagFilterRegistry()
        isDetailLoading = false
        resetDetailLog()
        pendingActionDestination = nil; renameState = .idle; deleteState = .idle; changeCategoryState = .idle
    }

    func resetDetailLog() {
        detailLogGeneration += 1
        detailLogState = .notLoaded
        detailLogDiagnosticsState = .idle
        detailExternalCreateSyncState = .idle
        detailTabRequest = nil
        iCloudConflictResolutionState = .idle
    }

    func locateMissingFile(fileID: Int64) async {
        guard canStartMissingFileRelink(fileID: fileID) else { return }
        missingFileRelinkState = .loading(fileID: fileID)

        do {
            let recoveryState = try await missingFileRecoverer.missingFileState(
                repoPath: repoPath,
                fileID: fileID
            )
            guard canApplyMissingFileRelinkResult(fileID: fileID) else { return }
            guard recoveryState.canLocate else {
                missingFileRelinkState = .unavailable(
                    fileID: fileID,
                    message: L10n.string("AreaMatrix cannot relink this missing file from its current state.")
                )
                return
            }
            guard let selectedURL = missingFilePicker.chooseReplacementFile(
                lastKnownPath: recoveryState.lastKnownPath
            ) else {
                missingFileRelinkState = .idle
                return
            }
            guard !fileResourceAccess.isICloudPlaceholder(selectedURL) else {
                missingFileRelinkState = .unavailable(
                    fileID: fileID,
                    message: L10n.string("Download the selected file in Finder, then choose Locate again.")
                )
                return
            }

            missingFileRelinkState = .relinking(fileID: fileID)
            let report = try await missingFileRecoverer.relinkMissingFile(
                repoPath: repoPath,
                fileID: fileID,
                newPath: selectedURL.path
            )
            try await applyMissingFileRelinkReport(report, fileID: fileID)
        } catch {
            guard canApplyMissingFileRelinkResult(fileID: fileID) else { return }
            let mapping = await mapCoreError(error)
            guard canApplyMissingFileRelinkResult(fileID: fileID) else { return }
            missingFileRelinkState = .failed(fileID: fileID, mapping)
        }
    }

    private func applyMissingFileRelinkReport(
        _ report: MissingFileRecoveryReportSnapshot,
        fileID: Int64
    ) async throws {
        switch report.status {
        case .relinked where report.hashMatched && !report.fileDeleted:
            if missingFileRelinkState.isBusy(for: fileID) {
                missingFileRelinkState = .idle
            }
            let loadedFile = try await fileDetailer.getFile(repoPath: repoPath, fileID: fileID)
            files = files.map { $0.id == loadedFile.id ? loadedFile : $0 }
            guard canApplyMissingFileRelinkResult(fileID: fileID) else { return }

            selectedFileDetail = loadedFile
            selectedFileNoteWriteBlock = noteWriteBlock(for: loadedFile)
            detailErrorMapping = nil
            statusBanner = .relinkedMissingFile(fileID: fileID)
            await loadSelectedFileChangeLog()
        case .hashMismatch:
            guard canApplyMissingFileRelinkResult(fileID: fileID) else { return }
            missingFileRelinkState = .hashMismatch(
                fileID: fileID,
                message: report.message ?? L10n.string("The selected file does not match the stored file hash.")
            )
        case .missing, .present, .relinked, .recordRemoved, .blocked:
            guard canApplyMissingFileRelinkResult(fileID: fileID) else { return }
            missingFileRelinkState = .unavailable(
                fileID: fileID,
                message: report.message ?? L10n.string("The selected file could not be relinked.")
            )
        }
    }

    private func canStartMissingFileRelink(fileID: Int64) -> Bool {
        let isCurrentSelection = selection.singleFileID == fileID || selectedFileDetail?.id == fileID
        return isCurrentSelection &&
            selectedFileDetail?.availability == .missing &&
            canPerformWriteAction(fileID: fileID) &&
            !missingFileRelinkState.isBusy(for: fileID)
    }

    private func canApplyMissingFileRelinkResult(fileID: Int64) -> Bool {
        selection.singleFileID == fileID && selectedFileDetail?.id == fileID
    }
}
