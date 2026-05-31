import Foundation

extension CommandPaletteSectionSnapshot {
    init(title: String, targets: [CommandTarget]) {
        self.title = title
        self.targets = targets.map(CommandTargetSnapshot.init(coreTarget:))
    }
}

extension CommandTargetGroupSnapshot {
    init(coreGroup: CommandTargetGroup) {
        switch coreGroup {
        case .commands:
            self = .commands
        case .navigation:
            self = .navigation
        case .currentSelection:
            self = .currentSelection
        case .recent:
            self = .recent
        case .smartLists:
            self = .smartLists
        case .fileCandidates:
            self = .fileCandidates
        }
    }
}

extension CommandTargetKindSnapshot {
    init(coreKind: CommandTargetKind) {
        switch coreKind {
        case .command:
            self = .command
        case .navigation:
            self = .navigation
        case .smartList:
            self = .smartList
        case .fileCandidate:
            self = .fileCandidate
        case .recentCommand:
            self = .recentCommand
        }
    }
}

extension CommandTargetActionSnapshot {
    init(coreAction: CommandTargetAction) {
        switch coreAction {
        case .navigate:
            self = .navigate
        case .openSheet:
            self = .openSheet
        case .openConfirmation:
            self = .openConfirmation
        case .runSmartList:
            self = .runSmartList
        case .focusFile:
            self = .focusFile
        case .openSearch:
            self = .openSearch
        case .lowRiskAction:
            self = .lowRiskAction
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
                reports[file.id] = try await aiTagSuggestionStore.suggestTagsWithAI(
                    repoPath: repoPath,
                    request: AiTagSuggestionRequest(fileId: file.id, candidateTags: [], privacyPolicyRef: nil)
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
