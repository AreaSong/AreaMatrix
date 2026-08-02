import Foundation

enum AIContentOwnershipState: String, Equatable {
    case generated
    case userOwned
}

enum ContentLocaleState: String, Equatable {
    case zhHans
    case en

    init(snapshotValue: String) throws {
        switch snapshotValue {
        case "zh-Hans": self = .zhHans
        case "en": self = .en
        default: throw CoreError.Config(reason: "unsupported concrete content locale")
        }
    }

    var snapshotValue: String {
        switch self {
        case .zhHans: "zh-Hans"
        case .en: "en"
        }
    }
}

enum AISummaryContextPolicyState: String, Equatable {
    case metadataOnly
    case metadataAndExtractedText
    case metadataTextAndNotes
}

enum AISummaryDraftStatusState: String, Equatable {
    case draft
    case skipped
    case unavailable
}

enum AISummaryInputFieldState: String, Equatable {
    case fileName
    case repoRelativePath
    case extractedTextExcerpt
    case existingAiSummary
    case noteSummary
    case tagCategoryContext
}

enum AISummaryProviderScopeState: String, Equatable {
    case localOnly
    case localPreferred
    case remoteAllowed
}

enum AISummaryRouteState: String, Equatable {
    case local
    case remote
}

enum AISummarySkipReasonState: String, Equatable {
    case aiDisabled
    case featureDisabled
    case providerUnavailable
    case privacyRule
    case noEligibleInput
    case callLogUnavailable
}

struct AISummaryClearReportSnapshot: Equatable {
    var fileID: Int64
    var cleared: Bool
    var contentRevision: Int64
    var clearedAt: Int64
}

struct AISummaryClearRequestSnapshot: Equatable {
    var fileID: Int64
    var expectedContentRevision: Int64
    var confirmed: Bool
}

struct AISummaryDraftSnapshot: Equatable {
    var operationID: String
    var contentLocale: ContentLocaleState
    var formatContractVersion: Int64
    var fileID: Int64
    var draftID: String?
    var status: AISummaryDraftStatusState
    var summaryText: String?
    var route: AISummaryRouteState?
    var modelName: String?
    var generatedAt: Int64?
    var usedContext: [AISummaryInputFieldState]
    var skippedReason: AISummarySkipReasonState?
    var privacyRuleID: String?
    var callLogID: Int64?
    var requiresUserSave: Bool
    var characterCount: Int64
}

struct AISummaryGenerationRequestSnapshot: Equatable {
    var operationID: String
    var retryOfOperationID: String?
    var fileID: Int64
    var providerScope: AISummaryProviderScopeState
    var contextPolicy: AISummaryContextPolicyState
    var privacyPolicyRef: String?
    var regenerateExisting: Bool
    var contentLocale: ContentLocaleState
}

struct AISummarySaveReportSnapshot: Equatable {
    var fileID: Int64
    var contentRevision: Int64
    var ownership: AIContentOwnershipState
    var savedSummary: String
    var savedAt: Int64
    var route: AISummaryRouteState?
    var modelName: String?
    var generatedAt: Int64?
    var usedContext: [AISummaryInputFieldState]
    var privacyRuleID: String?
    var callLogID: Int64?
    var operationID: String
    var contentLocale: ContentLocaleState
    var formatContractVersion: Int64
    var characterCount: Int64
}

struct AISummarySaveRequestSnapshot: Equatable {
    var fileID: Int64
    var expectedContentRevision: Int64
    var confirmReplaceUserOwned: Bool
    var summaryText: String
    var draftID: String?
    var route: AISummaryRouteState?
    var modelName: String?
    var generatedAt: Int64?
    var usedContext: [AISummaryInputFieldState]
    var privacyRuleID: String?
    var callLogID: Int64?
    var ownership: AIContentOwnershipState
    var operationID: String
    var contentLocale: ContentLocaleState
    var formatContractVersion: Int64
}

extension AISummaryClearReportSnapshot {
    init(coreReport: AiSummaryClearReport) {
        fileID = coreReport.fileId
        cleared = coreReport.cleared
        contentRevision = coreReport.contentRevision
        clearedAt = coreReport.clearedAt
    }
}

extension AiSummaryClearRequest {
    init(snapshot: AISummaryClearRequestSnapshot) {
        self.init(
            fileId: snapshot.fileID,
            expectedContentRevision: snapshot.expectedContentRevision,
            confirmed: snapshot.confirmed
        )
    }
}

extension AISummaryDraftSnapshot {
    init(coreDraft: AiSummaryDraft) {
        operationID = coreDraft.operationId
        contentLocale = ContentLocaleState(coreValue: coreDraft.contentLocale)
        formatContractVersion = coreDraft.formatContractVersion
        fileID = coreDraft.fileId
        draftID = coreDraft.draftId
        status = AISummaryDraftStatusState(coreStatus: coreDraft.status)
        summaryText = coreDraft.summaryText
        route = coreDraft.route.map(AISummaryRouteState.init(coreRoute:))
        modelName = coreDraft.modelName
        generatedAt = coreDraft.generatedAt
        usedContext = coreDraft.usedContext.map(AISummaryInputFieldState.init(coreField:))
        skippedReason = coreDraft.skippedReason.map(AISummarySkipReasonState.init(coreReason:))
        privacyRuleID = coreDraft.privacyRuleId
        callLogID = coreDraft.callLogId
        requiresUserSave = coreDraft.requiresUserSave
        characterCount = coreDraft.characterCount
    }
}

extension AiSummaryGenerationRequest {
    init(snapshot: AISummaryGenerationRequestSnapshot) {
        self.init(
            operationId: snapshot.operationID,
            retryOfOperationId: snapshot.retryOfOperationID,
            fileId: snapshot.fileID,
            providerScope: AiSummaryProviderScope(snapshotScope: snapshot.providerScope),
            contextPolicy: AiSummaryContextPolicy(snapshotPolicy: snapshot.contextPolicy),
            privacyPolicyRef: snapshot.privacyPolicyRef,
            regenerateExisting: snapshot.regenerateExisting,
            contentLocale: ContentLocale(snapshotLocale: snapshot.contentLocale)
        )
    }
}

extension AISummarySaveReportSnapshot {
    init(coreReport: AiSummarySaveReport) {
        fileID = coreReport.fileId
        contentRevision = coreReport.contentRevision
        ownership = AIContentOwnershipState(coreOwnership: coreReport.ownership)
        savedSummary = coreReport.savedSummary
        savedAt = coreReport.savedAt
        route = coreReport.route.map(AISummaryRouteState.init(coreRoute:))
        modelName = coreReport.modelName
        generatedAt = coreReport.generatedAt
        usedContext = coreReport.usedContext.map(AISummaryInputFieldState.init(coreField:))
        privacyRuleID = coreReport.privacyRuleId
        callLogID = coreReport.callLogId
        operationID = coreReport.operationId
        contentLocale = ContentLocaleState(coreValue: coreReport.contentLocale)
        formatContractVersion = coreReport.formatContractVersion
        characterCount = coreReport.characterCount
    }
}

extension AiSummarySaveRequest {
    init(snapshot: AISummarySaveRequestSnapshot) {
        self.init(
            fileId: snapshot.fileID,
            expectedContentRevision: snapshot.expectedContentRevision,
            confirmReplaceUserOwned: snapshot.confirmReplaceUserOwned,
            summaryText: snapshot.summaryText,
            draftId: snapshot.draftID,
            route: snapshot.route.map(AiSummaryRoute.init(snapshotRoute:)),
            modelName: snapshot.modelName,
            generatedAt: snapshot.generatedAt,
            usedContext: snapshot.usedContext.map(AiSummaryInputField.init(snapshotField:)),
            privacyRuleId: snapshot.privacyRuleID,
            callLogId: snapshot.callLogID,
            ownership: AiContentOwnership(snapshotOwnership: snapshot.ownership),
            operationId: snapshot.operationID,
            contentLocale: ContentLocale(snapshotLocale: snapshot.contentLocale),
            formatContractVersion: snapshot.formatContractVersion
        )
    }
}

private extension AIContentOwnershipState {
    init(coreOwnership: AiContentOwnership) {
        switch coreOwnership {
        case .generated: self = .generated
        case .userOwned: self = .userOwned
        }
    }
}

private extension ContentLocaleState {
    init(coreValue: ContentLocale) {
        switch coreValue {
        case .zhHans: self = .zhHans
        case .en: self = .en
        }
    }
}

private extension ContentLocale {
    init(snapshotLocale: ContentLocaleState) {
        switch snapshotLocale {
        case .zhHans: self = .zhHans
        case .en: self = .en
        }
    }
}

private extension AiContentOwnership {
    init(snapshotOwnership: AIContentOwnershipState) {
        switch snapshotOwnership {
        case .generated: self = .generated
        case .userOwned: self = .userOwned
        }
    }
}

private extension AISummaryContextPolicyState {
    init(corePolicy: AiSummaryContextPolicy) {
        switch corePolicy {
        case .metadataOnly: self = .metadataOnly
        case .metadataAndExtractedText: self = .metadataAndExtractedText
        case .metadataTextAndNotes: self = .metadataTextAndNotes
        }
    }
}

private extension AiSummaryContextPolicy {
    init(snapshotPolicy: AISummaryContextPolicyState) {
        switch snapshotPolicy {
        case .metadataOnly: self = .metadataOnly
        case .metadataAndExtractedText: self = .metadataAndExtractedText
        case .metadataTextAndNotes: self = .metadataTextAndNotes
        }
    }
}

private extension AISummaryDraftStatusState {
    init(coreStatus: AiSummaryDraftStatus) {
        switch coreStatus {
        case .draft: self = .draft
        case .skipped: self = .skipped
        case .unavailable: self = .unavailable
        }
    }
}

private extension AiSummaryDraftStatus {
    init(snapshotStatus: AISummaryDraftStatusState) {
        switch snapshotStatus {
        case .draft: self = .draft
        case .skipped: self = .skipped
        case .unavailable: self = .unavailable
        }
    }
}

private extension AISummaryInputFieldState {
    init(coreField: AiSummaryInputField) {
        switch coreField {
        case .fileName: self = .fileName
        case .repoRelativePath: self = .repoRelativePath
        case .extractedTextExcerpt: self = .extractedTextExcerpt
        case .existingAiSummary: self = .existingAiSummary
        case .noteSummary: self = .noteSummary
        case .tagCategoryContext: self = .tagCategoryContext
        }
    }
}

private extension AiSummaryInputField {
    init(snapshotField: AISummaryInputFieldState) {
        switch snapshotField {
        case .fileName: self = .fileName
        case .repoRelativePath: self = .repoRelativePath
        case .extractedTextExcerpt: self = .extractedTextExcerpt
        case .existingAiSummary: self = .existingAiSummary
        case .noteSummary: self = .noteSummary
        case .tagCategoryContext: self = .tagCategoryContext
        }
    }
}

private extension AiSummaryProviderScope {
    init(snapshotScope: AISummaryProviderScopeState) {
        switch snapshotScope {
        case .localOnly: self = .localOnly
        case .localPreferred: self = .localPreferred
        case .remoteAllowed: self = .remoteAllowed
        }
    }
}

private extension AISummaryRouteState {
    init(coreRoute: AiSummaryRoute) {
        switch coreRoute {
        case .local: self = .local
        case .remote: self = .remote
        }
    }
}

private extension AiSummaryRoute {
    init(snapshotRoute: AISummaryRouteState) {
        switch snapshotRoute {
        case .local: self = .local
        case .remote: self = .remote
        }
    }
}

private extension AISummarySkipReasonState {
    init(coreReason: AiSummarySkipReason) {
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

private extension AiSummarySkipReason {
    init(snapshotReason: AISummarySkipReasonState) {
        switch snapshotReason {
        case .aiDisabled: self = .aiDisabled
        case .featureDisabled: self = .featureDisabled
        case .providerUnavailable: self = .providerUnavailable
        case .privacyRule: self = .privacyRule
        case .noEligibleInput: self = .noEligibleInput
        case .callLogUnavailable: self = .callLogUnavailable
        }
    }
}
