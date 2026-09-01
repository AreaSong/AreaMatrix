import Foundation

extension DetailTagModel {
    func loadSelectedFileAITagSuggestions() async {
        guard let fileID = currentSelectedFileID else { return }
        await loadAITagSuggestions(fileID: fileID)
    }

    func retrySelectedFileAITagSuggestions() async {
        guard let fileID = currentSelectedFileID else { return }
        await loadAITagSuggestions(fileID: fileID)
    }

    func toggleSelectedFileAITagSuggestion(_ suggestionID: String) {
        aiSuggestionState = AITagSuggestionAction.toggling(suggestionID, in: aiSuggestionState)
    }

    func applySelectedFileAITagSuggestion(_ suggestionID: String) async -> BatchTagUndoState? {
        guard let item = AITagSuggestionAction.applyItem(suggestionID: suggestionID, in: aiSuggestionState) else {
            return nil
        }
        return await applyAITagSuggestions([item])
    }

    func selectHighConfidenceAITagSuggestions() {
        aiSuggestionState = AITagSuggestionAction.selectingHighConfidence(in: aiSuggestionState)
    }

    func clearSelectedFileAITagSuggestions() {
        aiSuggestionState = AITagSuggestionAction.clearingSelection(in: aiSuggestionState)
    }

    func startEditingSelectedFileAITagSuggestions() {
        aiSuggestionState = AITagSuggestionAction.startingEdit(
            in: aiSuggestionState,
            disabledReason: selectedAITagSuggestionDisabledReason()
        )
    }

    func cancelEditingSelectedFileAITagSuggestions() {
        aiSuggestionState = AITagSuggestionAction.cancelingEdit(in: aiSuggestionState)
    }

    func updateSelectedFileAITagSuggestionDisplayName(suggestionID: String, displayName: String) {
        aiSuggestionState = AITagSuggestionAction.updatingDisplayName(
            suggestionID: suggestionID,
            displayName: displayName,
            in: aiSuggestionState,
            disabledReason: selectedAITagSuggestionDisabledReason()
        )
    }

    func updateSelectedFileAITagSuggestionSlug(suggestionID: String, slug: String) {
        aiSuggestionState = AITagSuggestionAction.updatingSlug(
            suggestionID: suggestionID,
            slug: slug,
            in: aiSuggestionState,
            disabledReason: selectedAITagSuggestionDisabledReason()
        )
    }

    func regenerateSelectedFileAITagSuggestionSlug(suggestionID: String) {
        aiSuggestionState = AITagSuggestionAction.regeneratingSlug(
            suggestionID: suggestionID,
            in: aiSuggestionState,
            disabledReason: selectedAITagSuggestionDisabledReason()
        )
    }

    func applySelectedFileAITagSuggestions() async -> BatchTagUndoState? {
        await applyAITagSuggestions(AITagSuggestionAction.selectedApplyItems(in: aiSuggestionState))
    }

    func applyEditedSelectedFileAITagSuggestions() async -> BatchTagUndoState? {
        let items = AITagSuggestionAction.editedItems(in: aiSuggestionState)
        guard aiSuggestionState.editSession?.canApply == true else { return nil }
        return await applyAITagSuggestions(items, editedSession: aiSuggestionState.editSession)
    }

    func retryFailedSelectedFileAITagSuggestions() async -> BatchTagUndoState? {
        let items = AITagSuggestionAction.retryFailedItems(in: aiSuggestionState)
        return await applyAITagSuggestions(items, editedSession: aiSuggestionState.editSession)
    }
}

extension DetailTagModel {
    func loadAITagSuggestions(fileID: Int64) async {
        let previous = aiSuggestionState.report
        aiSuggestionState = .loading(fileID: fileID, previous: previous)
        do {
            let report = try await suggestAITagsWithPrivacyGate(
                fileID: fileID,
                file: currentSelectedFile(fileID),
                candidateTags: editorState.tagSet?.allKnownTags.map(\.value) ?? []
            )
            guard currentSelectedFileID == fileID else { return }
            aiSuggestionState = .loaded(
                fileID: fileID,
                report,
                AITagSuggestionAction.initialSelection(in: report)
            )
        } catch {
            let mapping = await mapCoreError(error)
            guard currentSelectedFileID == fileID else { return }
            aiSuggestionState = .failed(fileID: fileID, mapping, previous: previous)
        }
    }

    func suggestAITagsWithPrivacyGate(
        fileID: Int64,
        file: FileEntrySnapshot?,
        candidateTags: [String]
    ) async throws -> AITagSuggestionReportSnapshot {
        if let blockedReport = try await aiTagSettingsBlockedReport(fileID: fileID) {
            return blockedReport
        }
        let privacyGate = try await aiTagPrivacyGate(fileID: fileID, file: file)
        if let blockedReport = privacyGate.blockedReport {
            return blockedReport
        }
        return try await aiTagSuggestionStore.suggestTagsWithAI(
            repoPath: repoPath,
            request: AITagSuggestionRequestSnapshot(
                fileID: fileID,
                candidateTags: candidateTags,
                privacyPolicyRef: privacyGate.privacyPolicyRef
            )
        )
    }

    func applyAITagSuggestions(
        _ suggestions: [ApplyAITagSuggestionItemSnapshot],
        editedSession: AITagSuggestionEditSession? = nil
    ) async -> BatchTagUndoState? {
        guard let fileID = writableActionFileID(),
              let report = aiSuggestionState.report,
              !suggestions.isEmpty else { return nil }

        let previousTagSet = editorState.tagSet
        if let editedSession {
            aiSuggestionState = .applyingEdited(fileID: fileID, report: report, session: editedSession)
        } else {
            aiSuggestionState = .applying(
                fileID: fileID,
                report: report,
                selectedIDs: aiSuggestionState.selectedIDs
            )
        }
        editorState = .loading(fileID: fileID, previous: previousTagSet)

        do {
            let applyReport = try await aiTagSuggestionStore.applyAITagSuggestions(
                repoPath: repoPath,
                request: ApplyAITagSuggestionsRequestSnapshot(
                    fileId: fileID,
                    suggestions: suggestions,
                    callLogId: report.callLogId,
                    privacyRuleId: report.privacyRuleId,
                    confirmed: true
                )
            )
            guard currentSelectedFileID == fileID else { return nil }
            applyAITagSuggestionSuccess(report: report, applyReport: applyReport, editedSession: editedSession)
            await refreshChangeLog(fileID: fileID)
            return await loadSuggestionUndoState(undoToken: applyReport.undoToken)
        } catch {
            let mapping = await mapCoreError(error)
            guard currentSelectedFileID == fileID else { return nil }
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
        selectedWriteActionDisabledMessage(
            noSelectionMessage: L10n.string("Select a file before reviewing AI tag suggestions.")
        )
    }

    private func aiTagSettingsBlockedReport(fileID: Int64) async throws -> AITagSuggestionReportSnapshot? {
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
        reason: AITagSuggestionSkipReasonSnapshot,
        privacyRuleID: String? = nil
    ) -> AITagSuggestionReportSnapshot {
        AITagSuggestionReportSnapshot(
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

    private func aiTagPrivacyPolicyRef(from report: AIPrivacyEvaluationReportSnapshot) -> String? {
        guard report.skippedReason == .privacyRule || report.skippedReason == .fieldRule else { return nil }
        let ruleID = report.matchedRules.first?.ruleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let ruleID, !ruleID.isEmpty else { return "block:privacy-rule" }
        return "block:\(ruleID)"
    }

    private func aiTagProviderBlockedReason(for report: AIPrivacyEvaluationReportSnapshot)
        -> AITagSuggestionSkipReasonSnapshot? {
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
        snapshot: AIPrivacyRulesSnapshot
    ) -> AIPrivacyEvaluationRequestSnapshot {
        AIPrivacyEvaluationRequestSnapshot(
            feature: .autoTags,
            route: .remote,
            requestedFields: [
                .fileName, .repoRelativePath, .extension, .extractedTextExcerpt,
                .aiSummary, .noteSummary, .tagCategoryContext
            ],
            privacyGateEnabled: snapshot.privacyGateEnabled,
            providerScope: snapshot.providerScope,
            rules: snapshot.rules.map(AIPrivacyRuleInputSnapshot.init(summaryRule:)),
            remoteAllowedFields: snapshot.remoteAllowedFields.map(AIPrivacyFieldRuleSnapshot.init(state:)),
            context: aiTagPrivacyContext(fileID: fileID, file: file)
        )
    }

    private func aiTagPrivacyContext(fileID: Int64, file: FileEntrySnapshot?) -> AIPrivacyEvaluationContextSnapshot {
        AIPrivacyEvaluationContextSnapshot(
            fileId: fileID,
            repoRelativePath: file?.path,
            fileName: file?.currentName,
            category: file?.category,
            extension: file.flatMap { aiTagFileExtension($0.currentName) },
            tags: editorState.tagSet?.fileTags.map(\.value) ?? []
        )
    }

    private func aiTagFileExtension(_ filename: String) -> String? {
        let value = (filename as NSString).pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value.lowercased()
    }

    private func applyAITagSuggestionSuccess(
        report: AITagSuggestionReportSnapshot,
        applyReport: AITagSuggestionApplyReportSnapshot,
        editedSession: AITagSuggestionEditSession?
    ) {
        editorState = .loaded(fileID: applyReport.fileId, applyReport.tagSet)
        if let editedSession {
            aiSuggestionState = .editApplied(
                fileID: applyReport.fileId,
                report,
                applyReport,
                AITagSuggestionAction.sessionAfterApply(editedSession, report: applyReport)
            )
        } else {
            aiSuggestionState = .applied(
                fileID: applyReport.fileId,
                report,
                applyReport,
                aiSuggestionState.selectedIDs
            )
        }
    }

    private func applyAITagSuggestionFailure(
        mapping: CoreErrorMappingSnapshot,
        report: AITagSuggestionReportSnapshot,
        editedSession: AITagSuggestionEditSession?,
        previousTagSet: TagSetSnapshot?,
        submittedSlugs: [String]
    ) {
        if let editedSession {
            aiSuggestionState = .editing(fileID: report.fileId, report, editedSession)
        } else {
            aiSuggestionState = .failed(fileID: report.fileId, mapping, previous: report)
        }
        editorState = .failed(
            fileID: report.fileId,
            operation: .applySuggestions(submittedSlugs),
            mapping,
            previous: previousTagSet
        )
    }
}

private struct AITagPrivacyGateResult {
    var privacyPolicyRef: String?
    var blockedReport: AITagSuggestionReportSnapshot?
}
