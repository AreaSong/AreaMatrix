import Foundation

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
}

extension MainFileListModel {
    func loadAITagSuggestions(fileID: Int64) async {
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

    func suggestAITagsWithPrivacyGate(
        fileID: Int64,
        file: FileEntrySnapshot?,
        candidateTags: [String]
    ) async throws -> AiTagSuggestionReport {
        if let blockedReport = try await aiTagSettingsBlockedReport(fileID: fileID) {
            return blockedReport
        }
        let privacyGate = try await aiTagPrivacyGate(fileID: fileID, file: file)
        if let blockedReport = privacyGate.blockedReport {
            return blockedReport
        }
        return try await aiTagSuggestionStore.suggestTagsWithAI(
            repoPath: repoPath,
            request: AiTagSuggestionRequest(
                fileId: fileID,
                candidateTags: candidateTags,
                privacyPolicyRef: privacyGate.privacyPolicyRef
            )
        )
    }

    func applyAITagSuggestions(
        _ suggestions: [ApplyAiTagSuggestionItem],
        editedSession: AITagSuggestionEditSession? = nil
    ) async -> BatchTagUndoState? {
        guard let fileID = writableActionFileID(),
              let report = aiTagSuggestionState.report,
              !suggestions.isEmpty else { return nil }

        let previousTagSet = detailTagEditorState.tagSet
        if let editedSession {
            aiTagSuggestionState = .applyingEdited(fileID: fileID, report: report, session: editedSession)
        } else {
            aiTagSuggestionState = .applying(
                fileID: fileID,
                report: report,
                selectedIDs: aiTagSuggestionState.selectedIDs
            )
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

    func selectedAITagSuggestionDisabledReason() -> String? {
        selectedWriteActionDisabledMessage(noSelectionMessage: "Select a file before reviewing AI tag suggestions.")
    }

    private func aiTagSettingsBlockedReport(fileID: Int64) async throws -> AiTagSuggestionReport? {
        let snapshot = try await aiSettingsLoader.loadAISettings(repoPath: repoPath)
        let config = snapshot.config
        if !config.aiEnabled {
            return aiTagSkippedReport(fileID: fileID, reason: .aiDisabled)
        }
        guard let autoTags = config.featureToggles.first(where: { $0.feature == .autoTags }),
              autoTags.enabled else {
            return aiTagSkippedReport(fileID: fileID, reason: .featureDisabled)
        }
        return nil
    }

    private func aiTagSkippedReport(
        fileID: Int64,
        reason: AiTagSuggestionSkipReason,
        privacyRuleID: String? = nil
    ) -> AiTagSuggestionReport {
        AiTagSuggestionReport(
            fileId: fileID,
            status: .skipped,
            suggestions: [],
            route: nil,
            modelName: nil,
            generatedAt: nil,
            usedContext: [],
            skippedReason: reason,
            privacyRuleId: privacyRuleID,
            callLogId: nil,
            requiresUserConfirmation: true,
            confidenceThreshold: 0.8,
            contentsRead: false,
            aiUsed: false,
            networkUsed: false
        )
    }

    private func aiTagPrivacyGate(fileID: Int64, file: FileEntrySnapshot?) async throws -> AITagPrivacyGateResult {
        let snapshot = try await aiPrivacyRules.loadAIPrivacyRules(repoPath: repoPath)
        let report = try await aiPrivacyRules.evaluateAIPrivacy(
            repoPath: repoPath,
            request: aiTagPrivacyEvaluationRequest(fileID: fileID, file: file, snapshot: snapshot)
        )
        if let reason = aiTagProviderBlockedReason(for: report) {
            return AITagPrivacyGateResult(blockedReport: aiTagSkippedReport(fileID: fileID, reason: reason))
        }
        if let privacyPolicyRef = aiTagPrivacyPolicyRef(from: report) {
            return AITagPrivacyGateResult(privacyPolicyRef: privacyPolicyRef)
        }
        if report.decision != .allowed {
            return AITagPrivacyGateResult(blockedReport: aiTagSkippedReport(fileID: fileID, reason: .noEligibleInput))
        }
        return AITagPrivacyGateResult()
    }

    private func aiTagPrivacyPolicyRef(from report: AiPrivacyEvaluationReport) -> String? {
        guard report.skippedReason == .privacyRule || report.skippedReason == .fieldRule else { return nil }
        let ruleID = report.matchedRules.first?.ruleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let ruleID, !ruleID.isEmpty else { return "block:privacy-rule" }
        return "block:\(ruleID)"
    }

    private func aiTagProviderBlockedReason(for report: AiPrivacyEvaluationReport) -> AiTagSuggestionSkipReason? {
        if report.providerGateReason != nil { return .providerUnavailable }
        guard let skippedReason = report.skippedReason else { return nil }
        switch skippedReason {
        case .privacyRule, .fieldRule:
            return nil
        case .noEligibleInput:
            return .noEligibleInput
        case .privacyGateDisabled, .scopeNotAllowed, .providerNotConfigured,
             .providerNotVerified, .providerDisabled:
            return .providerUnavailable
        }
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
                .fileName, .repoRelativePath, .extension, .extractedTextExcerpt,
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
            aiTagSuggestionState = .applied(
                fileID: applyReport.fileId,
                report,
                applyReport,
                aiTagSuggestionState.selectedIDs
            )
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
}

private struct AITagPrivacyGateResult {
    var privacyPolicyRef: String?
    var blockedReport: AiTagSuggestionReport?
}
