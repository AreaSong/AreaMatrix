import Foundation

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

        aiTagBatchSuggestionState = .loading(AITagBatchSuggestionAction.initialReview(
            files: selectedFiles,
            reports: [:]
        ))
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
            disabledReason: writeActionDisabledMessage(fileID: fileID)
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
            disabledReason: writeActionDisabledMessage(fileID: fileID)
        )
    }

    func updateBatchAITagSuggestionSlug(fileID: Int64, suggestionID: String, slug: String) {
        aiTagBatchSuggestionState = AITagBatchSuggestionAction.updatingSlug(
            fileID: fileID,
            suggestionID: suggestionID,
            slug: slug,
            in: aiTagBatchSuggestionState,
            disabledReason: writeActionDisabledMessage(fileID: fileID)
        )
    }

    func regenerateBatchAITagSuggestionSlug(fileID: Int64, suggestionID: String) {
        aiTagBatchSuggestionState = AITagBatchSuggestionAction.regeneratingSlug(
            fileID: fileID,
            suggestionID: suggestionID,
            in: aiTagBatchSuggestionState,
            disabledReason: writeActionDisabledMessage(fileID: fileID)
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
        var reports: [Int64: AITagSuggestionReportSnapshot] = [:]
        var failures: [Int64: CoreErrorMappingSnapshot] = [:]
        for file in files {
            do {
                reports[file.id] = try await suggestAITagsWithPrivacyGate(
                    fileID: file.id,
                    file: file,
                    candidateTags: []
                )
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
    ) async -> (applyReport: AITagSuggestionApplyReportSnapshot?, failure: CoreErrorMappingSnapshot?) {
        guard let report = review.reports[fileID] else { return (nil, nil) }
        let items = review.applyItems(fileID: fileID)
        guard !items.isEmpty, canPerformWriteAction(fileID: fileID) else { return (nil, nil) }

        do {
            let applyReport = try await aiTagSuggestionStore.applyAITagSuggestions(
                repoPath: repoPath,
                request: ApplyAITagSuggestionsRequestSnapshot(
                    fileId: fileID,
                    suggestions: items,
                    callLogId: report.callLogId,
                    privacyRuleId: report.privacyRuleId,
                    confirmed: true
                )
            )
            return (applyReport, nil)
        } catch {
            return await (nil, mapCoreError(error))
        }
    }

    private func failedSuggestionIDs(in report: AITagSuggestionApplyReportSnapshot) -> Set<String> {
        Set(report.itemResults.compactMap { $0.status == .failed ? $0.suggestionId : nil })
    }
}
