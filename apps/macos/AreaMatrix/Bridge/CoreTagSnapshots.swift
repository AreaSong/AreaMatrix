import AreaMatrixCoreBridgeContract
import Foundation

typealias AITagSuggestionRequestSnapshot = AreaMatrixCoreBridgeContract.AITagSuggestionRequestSnapshot
typealias AITagSuggestionRouteSnapshot = AreaMatrixCoreBridgeContract.AITagSuggestionRouteSnapshot
typealias AITagSuggestionInputFieldSnapshot = AreaMatrixCoreBridgeContract.AITagSuggestionInputFieldSnapshot
typealias AITagSuggestionReportStatusSnapshot = AreaMatrixCoreBridgeContract.AITagSuggestionReportStatusSnapshot
typealias AITagSuggestionSkipReasonSnapshot = AreaMatrixCoreBridgeContract.AITagSuggestionSkipReasonSnapshot
typealias AITagSuggestionCandidateStatusSnapshot =
    AreaMatrixCoreBridgeContract.AITagSuggestionCandidateStatusSnapshot
typealias AITagSuggestionMergeActionSnapshot = AreaMatrixCoreBridgeContract.AITagSuggestionMergeActionSnapshot
typealias AITagSuggestionApplyStatusSnapshot = AreaMatrixCoreBridgeContract.AITagSuggestionApplyStatusSnapshot
typealias AITagSuggestionSnapshot = AreaMatrixCoreBridgeContract.AITagSuggestionSnapshot
typealias AITagSuggestionReportSnapshot = AreaMatrixCoreBridgeContract.AITagSuggestionReportSnapshot
typealias ApplyAITagSuggestionItemSnapshot = AreaMatrixCoreBridgeContract.ApplyAITagSuggestionItemSnapshot
typealias ApplyAITagSuggestionsRequestSnapshot = AreaMatrixCoreBridgeContract.ApplyAITagSuggestionsRequestSnapshot
typealias AITagSuggestionApplyItemResultSnapshot =
    AreaMatrixCoreBridgeContract.AITagSuggestionApplyItemResultSnapshot
typealias AITagSuggestionApplyReportSnapshot = AreaMatrixCoreBridgeContract.AITagSuggestionApplyReportSnapshot
typealias TagRecordSnapshot = AreaMatrixCoreBridgeContract.TagRecordSnapshot
typealias TagSetSnapshot = AreaMatrixCoreBridgeContract.TagSetSnapshot
typealias BatchMutationStatusSnapshot = AreaMatrixCoreBridgeContract.BatchMutationStatusSnapshot
typealias BatchMutationItemResultSnapshot = AreaMatrixCoreBridgeContract.BatchMutationItemResultSnapshot
typealias BatchMutationReportSnapshot = AreaMatrixCoreBridgeContract.BatchMutationReportSnapshot
typealias TagSuggestionContextSnapshot = AreaMatrixCoreBridgeContract.TagSuggestionContextSnapshot
typealias TagSuggestionRequestSnapshot = AreaMatrixCoreBridgeContract.TagSuggestionRequestSnapshot
typealias TagSuggestionSourceSnapshot = AreaMatrixCoreBridgeContract.TagSuggestionSourceSnapshot
typealias TagSuggestionMatchSnapshot = AreaMatrixCoreBridgeContract.TagSuggestionMatchSnapshot
typealias TagSuggestionStatusSnapshot = AreaMatrixCoreBridgeContract.TagSuggestionStatusSnapshot
typealias TagSuggestionSnapshot = AreaMatrixCoreBridgeContract.TagSuggestionSnapshot
typealias TagSuggestionReportSnapshot = AreaMatrixCoreBridgeContract.TagSuggestionReportSnapshot
typealias ApplyTagSuggestionItemSnapshot = AreaMatrixCoreBridgeContract.ApplyTagSuggestionItemSnapshot
typealias ApplyTagSuggestionsRequestSnapshot = AreaMatrixCoreBridgeContract.ApplyTagSuggestionsRequestSnapshot
typealias TagSuggestionApplyStatusSnapshot = AreaMatrixCoreBridgeContract.TagSuggestionApplyStatusSnapshot
typealias TagSuggestionApplyItemResultSnapshot =
    AreaMatrixCoreBridgeContract.TagSuggestionApplyItemResultSnapshot
typealias TagSuggestionApplyReportSnapshot = AreaMatrixCoreBridgeContract.TagSuggestionApplyReportSnapshot

extension AITagSuggestionReportSnapshot {
    init(coreReport: AiTagSuggestionReport) {
        self.init(
            fileId: coreReport.fileId,
            status: AITagSuggestionReportStatusSnapshot(coreStatus: coreReport.status),
            suggestions: coreReport.suggestions.map(AITagSuggestionSnapshot.init(coreSuggestion:)),
            route: coreReport.route.map(AITagSuggestionRouteSnapshot.init(coreRoute:)),
            modelName: coreReport.modelName,
            generatedAt: coreReport.generatedAt,
            usedContext: coreReport.usedContext.map(AITagSuggestionInputFieldSnapshot.init(coreField:)),
            skippedReason: coreReport.skippedReason.map(AITagSuggestionSkipReasonSnapshot.init(coreReason:)),
            privacyRuleId: coreReport.privacyRuleId,
            callLogId: coreReport.callLogId,
            requiresUserConfirmation: coreReport.requiresUserConfirmation,
            confidenceThreshold: coreReport.confidenceThreshold,
            contentsRead: coreReport.contentsRead,
            aiUsed: coreReport.aiUsed,
            networkUsed: coreReport.networkUsed
        )
    }
}

private extension AITagSuggestionSnapshot {
    init(coreSuggestion: AiTagSuggestion) {
        self.init(
            suggestionId: coreSuggestion.suggestionId,
            slug: coreSuggestion.slug,
            displayName: coreSuggestion.displayName,
            confidence: coreSuggestion.confidence,
            reason: coreSuggestion.reason,
            status: AITagSuggestionCandidateStatusSnapshot(coreStatus: coreSuggestion.status),
            mergeAction: AITagSuggestionMergeActionSnapshot(coreAction: coreSuggestion.mergeAction),
            matchedExistingSlug: coreSuggestion.matchedExistingSlug,
            selectedByDefault: coreSuggestion.selectedByDefault,
            disabledReason: coreSuggestion.disabledReason
        )
    }
}

extension ApplyAiTagSuggestionsRequest {
    init(snapshot: ApplyAITagSuggestionsRequestSnapshot) {
        self.init(
            fileId: snapshot.fileId,
            suggestions: snapshot.suggestions.map(ApplyAiTagSuggestionItem.init(snapshot:)),
            callLogId: snapshot.callLogId,
            privacyRuleId: snapshot.privacyRuleId,
            confirmed: snapshot.confirmed
        )
    }
}

private extension ApplyAiTagSuggestionItem {
    init(snapshot: ApplyAITagSuggestionItemSnapshot) {
        self.init(
            suggestionId: snapshot.suggestionId,
            slug: snapshot.slug,
            displayName: snapshot.displayName,
            confidence: snapshot.confidence,
            editedByUser: snapshot.editedByUser,
            mergeTargetSlug: snapshot.mergeTargetSlug
        )
    }
}

extension AITagSuggestionApplyReportSnapshot {
    init(coreReport: AiTagSuggestionApplyReport) {
        self.init(
            fileId: coreReport.fileId,
            requestedCount: coreReport.requestedCount,
            appliedCount: coreReport.appliedCount,
            skippedCount: coreReport.skippedCount,
            failedCount: coreReport.failedCount,
            itemResults: coreReport.itemResults.map(AITagSuggestionApplyItemResultSnapshot.init(coreResult:)),
            tagSet: TagSetSnapshot(coreTagSet: coreReport.tagSet),
            undoToken: coreReport.undoToken,
            callLogId: coreReport.callLogId,
            refreshTargets: coreReport.refreshTargets
        )
    }
}

private extension AITagSuggestionApplyItemResultSnapshot {
    init(coreResult: AiTagSuggestionApplyItemResult) {
        self.init(
            suggestionId: coreResult.suggestionId,
            slug: coreResult.slug,
            status: AITagSuggestionApplyStatusSnapshot(coreStatus: coreResult.status),
            error: coreResult.error
        )
    }
}

private extension AITagSuggestionRouteSnapshot {
    init(coreRoute: AiTagSuggestionRoute) {
        switch coreRoute {
        case .local: self = .local
        case .remote: self = .remote
        }
    }
}

private extension AITagSuggestionInputFieldSnapshot {
    init(coreField: AiTagSuggestionInputField) {
        switch coreField {
        case .fileName: self = .fileName
        case .repoRelativePath: self = .repoRelativePath
        case .extractedTextExcerpt: self = .extractedTextExcerpt
        case .aiSummary: self = .aiSummary
        case .noteSummary: self = .noteSummary
        case .existingTags: self = .existingTags
        case .tagRegistry: self = .tagRegistry
        }
    }
}

private extension AITagSuggestionReportStatusSnapshot {
    init(coreStatus: AiTagSuggestionReportStatus) {
        switch coreStatus {
        case .suggested: self = .suggested
        case .noSuggestion: self = .noSuggestion
        case .skipped: self = .skipped
        case .unavailable: self = .unavailable
        }
    }
}

private extension AITagSuggestionSkipReasonSnapshot {
    init(coreReason: AiTagSuggestionSkipReason) {
        switch coreReason {
        case .aiDisabled: self = .aiDisabled
        case .featureDisabled: self = .featureDisabled
        case .providerUnavailable: self = .providerUnavailable
        case .privacyRule: self = .privacyRule
        case .noEligibleInput: self = .noEligibleInput
        case .callLogUnavailable: self = .callLogUnavailable
        }
    }
}

private extension AITagSuggestionCandidateStatusSnapshot {
    init(coreStatus: AiTagSuggestionCandidateStatus) {
        switch coreStatus {
        case .suggested: self = .suggested
        case .lowConfidence: self = .lowConfidence
        case .alreadyApplied: self = .alreadyApplied
        case .invalid: self = .invalid
        case .blocked: self = .blocked
        }
    }
}

private extension AITagSuggestionMergeActionSnapshot {
    init(coreAction: AiTagSuggestionMergeAction) {
        switch coreAction {
        case .createTag: self = .createTag
        case .useExistingTag: self = .useExistingTag
        case .mergeWithExistingTag: self = .mergeWithExistingTag
        }
    }
}

private extension AITagSuggestionApplyStatusSnapshot {
    init(coreStatus: AiTagSuggestionApplyStatus) {
        switch coreStatus {
        case .applied: self = .applied
        case .alreadyAdded: self = .alreadyAdded
        case .failed: self = .failed
        }
    }
}

extension TagSetSnapshot {
    init(coreTagSet: TagSet) {
        self.init(
            fileID: coreTagSet.fileId,
            fileTags: coreTagSet.fileTags.map(TagRecordSnapshot.init(coreRecord:)),
            availableTags: coreTagSet.availableTags.map(TagRecordSnapshot.init(coreRecord:)),
            recentTags: coreTagSet.recentTags.map(TagRecordSnapshot.init(coreRecord:)),
            updatedAt: coreTagSet.updatedAt
        )
    }
}

private extension TagRecordSnapshot {
    init(coreRecord: TagRecord) {
        self.init(
            value: coreRecord.value,
            label: coreRecord.label,
            fileCount: coreRecord.fileCount,
            selected: coreRecord.selected,
            disabled: coreRecord.disabled,
            updatedAt: coreRecord.updatedAt
        )
    }
}

extension BatchMutationReportSnapshot {
    init(coreReport: BatchMutationReport) {
        self.init(
            requestedFileCount: coreReport.requestedFileCount,
            requestedTagCount: coreReport.requestedTagCount,
            addedCount: coreReport.addedCount,
            skippedCount: coreReport.skippedCount,
            failedCount: coreReport.failedCount,
            itemResults: coreReport.itemResults.map(BatchMutationItemResultSnapshot.init(coreResult:)),
            undoToken: coreReport.undoToken
        )
    }
}

extension TagSuggestionSourceSnapshot {
    var displayName: String {
        switch self {
        case .fileName: L10n.string("File name")
        case .path: L10n.string("Path")
        case .sourceFolder: L10n.string("Source folder")
        case .existingTagPattern: L10n.string("Existing tag pattern")
        }
    }
}

extension TagSuggestionMatchSnapshot {
    var displayName: String {
        switch self {
        case .strong: L10n.string("Strong match")
        case .weak: L10n.string("Weak match")
        }
    }
}

extension TagSuggestionStatusSnapshot {
    var displayName: String {
        switch self {
        case .newTag: L10n.string("New tag")
        case .alreadyAdded: L10n.string("Already added")
        case .invalid: L10n.string("Invalid")
        case .blocked: L10n.string("Blocked")
        }
    }
}

extension TagSuggestionContext {
    init(snapshot: TagSuggestionContextSnapshot) {
        self.init(sourceFolder: snapshot.sourceFolder, sourceKeywords: snapshot.sourceKeywords)
    }
}

extension TagSuggestionRequest {
    init(snapshot: TagSuggestionRequestSnapshot) {
        self.init(
            fileId: snapshot.fileID,
            context: snapshot.context.map(TagSuggestionContext.init(snapshot:)),
            limit: snapshot.limit
        )
    }
}

extension ApplyTagSuggestionItem {
    init(snapshot: ApplyTagSuggestionItemSnapshot) {
        self.init(
            suggestionId: snapshot.suggestionID,
            slug: snapshot.slug,
            displayName: snapshot.displayName
        )
    }
}

extension ApplyTagSuggestionsRequest {
    init(snapshot: ApplyTagSuggestionsRequestSnapshot) {
        self.init(
            fileId: snapshot.fileID,
            suggestions: snapshot.suggestions.map(ApplyTagSuggestionItem.init(snapshot:))
        )
    }
}

extension TagSuggestionReportSnapshot {
    init(coreReport: TagSuggestionReport) {
        self.init(
            fileID: coreReport.fileId,
            suggestions: coreReport.suggestions.map(TagSuggestionSnapshot.init(coreSuggestion:)),
            tagSet: TagSetSnapshot(coreTagSet: coreReport.tagSet),
            contentsRead: coreReport.contentsRead,
            aiUsed: coreReport.aiUsed,
            networkUsed: coreReport.networkUsed
        )
    }
}

private extension TagSuggestionSnapshot {
    init(coreSuggestion: TagSuggestion) {
        self.init(
            suggestionID: coreSuggestion.suggestionId,
            slug: coreSuggestion.slug,
            displayName: coreSuggestion.displayName,
            reason: coreSuggestion.reason,
            source: TagSuggestionSourceSnapshot(coreSource: coreSuggestion.source),
            matchStrength: TagSuggestionMatchSnapshot(coreMatch: coreSuggestion.matchStrength),
            alreadyExists: coreSuggestion.alreadyExists,
            needsCreate: coreSuggestion.needsCreate,
            status: TagSuggestionStatusSnapshot(coreStatus: coreSuggestion.status),
            selectedByDefault: coreSuggestion.selectedByDefault,
            disabledReason: coreSuggestion.disabledReason
        )
    }
}

private extension TagSuggestionSourceSnapshot {
    init(coreSource: TagSuggestionSource) {
        switch coreSource {
        case .fileName: self = .fileName
        case .path: self = .path
        case .sourceFolder: self = .sourceFolder
        case .existingTagPattern: self = .existingTagPattern
        }
    }
}

private extension TagSuggestionMatchSnapshot {
    init(coreMatch: TagSuggestionMatch) {
        switch coreMatch {
        case .strong: self = .strong
        case .weak: self = .weak
        }
    }
}

private extension TagSuggestionStatusSnapshot {
    init(coreStatus: TagSuggestionStatus) {
        switch coreStatus {
        case .newTag: self = .newTag
        case .alreadyAdded: self = .alreadyAdded
        case .invalid: self = .invalid
        case .blocked: self = .blocked
        }
    }
}

private extension BatchMutationItemResultSnapshot {
    init(coreResult: BatchMutationItemResult) {
        self.init(
            fileID: coreResult.fileId,
            tag: coreResult.tag,
            status: BatchMutationStatusSnapshot(coreStatus: coreResult.status),
            error: coreResult.error
        )
    }
}

private extension BatchMutationStatusSnapshot {
    init(coreStatus: BatchMutationStatus) {
        switch coreStatus {
        case .added:
            self = .added
        case .alreadyHadTag:
            self = .alreadyHadTag
        case .failed:
            self = .failed
        }
    }
}
