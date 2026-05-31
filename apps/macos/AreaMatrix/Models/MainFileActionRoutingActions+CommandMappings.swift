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
    func loadSelectedFileAITagSuggestions() async {
        guard let fileID = selection.singleFileID else { return }
        await loadAITagSuggestions(fileID: fileID)
    }

    func retrySelectedFileAITagSuggestions() async {
        guard let fileID = selection.singleFileID else { return }
        await loadAITagSuggestions(fileID: fileID)
    }

    func toggleSelectedFileAITagSuggestion(_ suggestionID: String) {
        aiTagSuggestionState = AITagSuggestionAction.toggling(suggestionID, in: aiTagSuggestionState)
    }

    func applySelectedFileAITagSuggestion(_ suggestionID: String) async -> BatchTagUndoState? {
        guard let item = AITagSuggestionAction.applyItem(suggestionID: suggestionID, in: aiTagSuggestionState) else {
            return nil
        }
        return await applyAITagSuggestions([item])
    }

    func selectHighConfidenceAITagSuggestions() {
        aiTagSuggestionState = AITagSuggestionAction.selectingHighConfidence(in: aiTagSuggestionState)
    }

    func clearSelectedFileAITagSuggestions() {
        aiTagSuggestionState = AITagSuggestionAction.clearingSelection(in: aiTagSuggestionState)
    }

    func startEditingSelectedFileAITagSuggestions() {
        aiTagSuggestionState = AITagSuggestionAction.startingEdit(
            in: aiTagSuggestionState,
            disabledReason: selectedAITagSuggestionDisabledReason()
        )
    }

    func cancelEditingSelectedFileAITagSuggestions() {
        aiTagSuggestionState = AITagSuggestionAction.cancelingEdit(in: aiTagSuggestionState)
    }

    func updateSelectedFileAITagSuggestionDisplayName(suggestionID: String, displayName: String) {
        aiTagSuggestionState = AITagSuggestionAction.updatingDisplayName(
            suggestionID: suggestionID,
            displayName: displayName,
            in: aiTagSuggestionState,
            disabledReason: selectedAITagSuggestionDisabledReason()
        )
    }

    func updateSelectedFileAITagSuggestionSlug(suggestionID: String, slug: String) {
        aiTagSuggestionState = AITagSuggestionAction.updatingSlug(
            suggestionID: suggestionID,
            slug: slug,
            in: aiTagSuggestionState,
            disabledReason: selectedAITagSuggestionDisabledReason()
        )
    }

    func regenerateSelectedFileAITagSuggestionSlug(suggestionID: String) {
        aiTagSuggestionState = AITagSuggestionAction.regeneratingSlug(
            suggestionID: suggestionID,
            in: aiTagSuggestionState,
            disabledReason: selectedAITagSuggestionDisabledReason()
        )
    }

    func applySelectedFileAITagSuggestions() async -> BatchTagUndoState? {
        await applyAITagSuggestions(AITagSuggestionAction.selectedApplyItems(in: aiTagSuggestionState))
    }

    func applyEditedSelectedFileAITagSuggestions() async -> BatchTagUndoState? {
        let items = AITagSuggestionAction.editedItems(in: aiTagSuggestionState)
        guard aiTagSuggestionState.editSession?.canApply == true else { return nil }
        return await applyAITagSuggestions(items, editedSession: aiTagSuggestionState.editSession)
    }

    func retryFailedSelectedFileAITagSuggestions() async -> BatchTagUndoState? {
        let items = AITagSuggestionAction.retryFailedItems(in: aiTagSuggestionState)
        return await applyAITagSuggestions(items, editedSession: aiTagSuggestionState.editSession)
    }

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

    private func loadAITagSuggestions(fileID: Int64) async {
        let previous = aiTagSuggestionState.report
        aiTagSuggestionState = .loading(fileID: fileID, previous: previous)
        do {
            let report = try await suggestAITagsWithPrivacyGate(
                fileID: fileID,
                file: selectedFileDetail ?? cachedFile(id: fileID),
                candidateTags: detailTagEditorState.tagSet?.allKnownTags.map(\.value) ?? []
            )
            guard selection.singleFileID == fileID else { return }
            aiTagSuggestionState = .loaded(
                fileID: fileID,
                report,
                AITagSuggestionAction.initialSelection(in: report)
            )
        } catch {
            let mapping = await mapCoreError(error)
            guard selection.singleFileID == fileID else { return }
            aiTagSuggestionState = .failed(fileID: fileID, mapping, previous: previous)
        }
    }

    private func suggestAITagsWithPrivacyGate(
        fileID: Int64,
        file: FileEntrySnapshot?,
        candidateTags: [String]
    ) async throws -> AiTagSuggestionReport {
        let privacyPolicyRef = try await aiTagPrivacyPolicyRef(fileID: fileID, file: file)
        return try await aiTagSuggestionStore.suggestTagsWithAI(
            repoPath: repoPath,
            request: AiTagSuggestionRequest(
                fileId: fileID,
                candidateTags: candidateTags,
                privacyPolicyRef: privacyPolicyRef
            )
        )
    }

    private func aiTagPrivacyPolicyRef(fileID: Int64, file: FileEntrySnapshot?) async throws -> String? {
        let snapshot = try await aiPrivacyRules.loadAIPrivacyRules(repoPath: repoPath)
        let report = try await aiPrivacyRules.evaluateAIPrivacy(
            repoPath: repoPath,
            request: aiTagPrivacyEvaluationRequest(fileID: fileID, file: file, snapshot: snapshot)
        )
        guard report.skippedReason == .privacyRule || report.skippedReason == .fieldRule else { return nil }
        let ruleID = report.matchedRules.first?.ruleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let ruleID, !ruleID.isEmpty else { return "block:privacy-rule" }
        return "block:\(ruleID)"
    }

    private func aiTagPrivacyEvaluationRequest(
        fileID: Int64,
        file: FileEntrySnapshot?,
        snapshot: AiPrivacyRulesSnapshot
    ) -> AiPrivacyEvaluationRequest {
        AiPrivacyEvaluationRequest(
            feature: .autoTags,
            route: .remote,
            requestedFields: [
                .fileName, .repoRelativePath, .`extension`, .extractedTextExcerpt,
                .aiSummary, .noteSummary, .tagCategoryContext
            ],
            privacyGateEnabled: snapshot.privacyGateEnabled,
            providerScope: snapshot.providerScope,
            rules: snapshot.rules.map(AiPrivacyRuleInput.init(summaryRule:)),
            remoteAllowedFields: snapshot.remoteAllowedFields.map(AiPrivacyFieldRule.init(state:)),
            context: aiTagPrivacyContext(fileID: fileID, file: file)
        )
    }

    private func aiTagPrivacyContext(fileID: Int64, file: FileEntrySnapshot?) -> AiPrivacyEvaluationContext {
        AiPrivacyEvaluationContext(
            fileId: fileID,
            repoRelativePath: file?.path,
            fileName: file?.currentName,
            category: file?.category,
            extension: file.flatMap { aiTagFileExtension($0.currentName) },
            tags: detailTagEditorState.tagSet?.fileTags.map(\.value) ?? []
        )
    }

    private func aiTagFileExtension(_ filename: String) -> String? {
        let value = (filename as NSString).pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value.lowercased()
    }

    private func applyAITagSuggestions(
        _ suggestions: [ApplyAiTagSuggestionItem],
        editedSession: AITagSuggestionEditSession? = nil
    ) async -> BatchTagUndoState? {
        guard let fileID = selection.singleFileID,
              writeActionDisabledReason(fileID: fileID) == nil,
              let report = aiTagSuggestionState.report,
              !suggestions.isEmpty else { return nil }

        let previousTagSet = detailTagEditorState.tagSet
        if let editedSession {
            aiTagSuggestionState = .applyingEdited(fileID: fileID, report: report, session: editedSession)
        } else {
            aiTagSuggestionState = .applying(fileID: fileID, report: report, selectedIDs: aiTagSuggestionState.selectedIDs)
        }
        detailTagEditorState = .loading(fileID: fileID, previous: previousTagSet)

        do {
            let applyReport = try await aiTagSuggestionStore.applyAITagSuggestions(
                repoPath: repoPath,
                request: ApplyAiTagSuggestionsRequest(
                    fileId: fileID,
                    suggestions: suggestions,
                    callLogId: report.callLogId,
                    privacyRuleId: report.privacyRuleId,
                    confirmed: true
                )
            )
            guard selection.singleFileID == fileID else { return nil }
            applyAITagSuggestionSuccess(report: report, applyReport: applyReport, editedSession: editedSession)
            await loadChangeLog(fileID: fileID)
            return await loadSuggestionUndoState(undoToken: applyReport.undoToken)
        } catch {
            let mapping = await mapCoreError(error)
            guard selection.singleFileID == fileID else { return nil }
            applyAITagSuggestionFailure(
                mapping: mapping,
                report: report,
                editedSession: editedSession,
                previousTagSet: previousTagSet,
                submittedSlugs: suggestions.map(\.slug)
            )
            return nil
        }
    }

    private func applyAITagSuggestionSuccess(
        report: AiTagSuggestionReport,
        applyReport: AiTagSuggestionApplyReport,
        editedSession: AITagSuggestionEditSession?
    ) {
        detailTagEditorState = .loaded(fileID: applyReport.fileId, TagSetSnapshot(coreTagSet: applyReport.tagSet))
        if let editedSession {
            aiTagSuggestionState = .editApplied(
                fileID: applyReport.fileId,
                report,
                applyReport,
                AITagSuggestionAction.sessionAfterApply(editedSession, report: applyReport)
            )
        } else {
            aiTagSuggestionState = .applied(fileID: applyReport.fileId, report, applyReport, aiTagSuggestionState.selectedIDs)
        }
    }

    private func applyAITagSuggestionFailure(
        mapping: CoreErrorMappingSnapshot,
        report: AiTagSuggestionReport,
        editedSession: AITagSuggestionEditSession?,
        previousTagSet: TagSetSnapshot?,
        submittedSlugs: [String]
    ) {
        if let editedSession {
            aiTagSuggestionState = .editing(fileID: report.fileId, report, editedSession)
        } else {
            aiTagSuggestionState = .failed(fileID: report.fileId, mapping, previous: report)
        }
        detailTagEditorState = .failed(
            fileID: report.fileId,
            operation: .applySuggestions(submittedSlugs),
            mapping,
            previous: previousTagSet
        )
    }

    private func selectedAITagSuggestionDisabledReason() -> String? {
        guard let fileID = selection.singleFileID else { return "Select a file before reviewing AI tag suggestions." }
        return writeActionDisabledReason(fileID: fileID)?.rawValue
    }
}
