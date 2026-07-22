import Foundation

protocol CoreClassifierRuleSaving: Sendable {
    func saveClassifierRule(repoPath: String, rule: ClassifierRuleSnapshot) async throws -> ClassifierRuleSnapshot
}

protocol CoreClassifierImpactPreviewing: Sendable {
    func previewClassifierRuleImpact(
        repoPath: String,
        request: ClassifierImpactPreviewRequestSnapshot
    ) async throws -> RuleImpactReportSnapshot
}

struct ClassifierRuleSnapshot: Equatable {
    var targetCategory: String
    var keywords: [String]
    var extensions: [String]
    var priority: Int64
    var previewConfirmed: Bool
}

enum ClassifierImpactPreviewModeSnapshot: String, Equatable {
    case ruleDraft = "RuleDraft"
    case removeKeyword = "RemoveKeyword"
    case removeExtension = "RemoveExtension"
    case removeCategory = "RemoveCategory"
}

struct ClassifierImpactPreviewRequestSnapshot: Equatable {
    var mode: ClassifierImpactPreviewModeSnapshot
    var rule: ClassifierRuleSnapshot
    var moveFiles: Bool
    var replacementCategory: String?
}

enum RuleImpactMatchReasonSnapshot: String, Equatable {
    case keyword = "Keyword"
    case `extension` = "Extension"
    case category = "Category"

    var displayLabel: String {
        switch self {
        case .keyword: L10n.string("Keyword")
        case .extension: L10n.string("Extension")
        case .category: L10n.string("Category")
        }
    }
}

enum RuleImpactStatusSnapshot: String, Equatable {
    case willUpdate = "Will update"
    case alreadyCorrect = "Already correct"
    case needsReview = "Needs review"
    case conflict = "Name conflict if moved"
    case missing = "Missing file"
    case indexOnly = "Index-only"

    var displayName: String {
        switch self {
        case .willUpdate: L10n.string("Will update")
        case .alreadyCorrect: L10n.string("Already correct")
        case .needsReview: L10n.string("Needs review")
        case .conflict: L10n.string("Name conflict if moved")
        case .missing: L10n.string("Missing file")
        case .indexOnly: L10n.string("Index-only")
        }
    }
}

enum RuleImpactConflictKindSnapshot: String, Equatable {
    case nameConflict = "NameConflict"
    case missingFile = "MissingFile"
    case unsupportedStorage = "UnsupportedStorage"
    case ruleConflict = "RuleConflict"
}

struct RuleImpactSampleSnapshot: Equatable, Identifiable {
    var fileID: Int64
    var path: String
    var currentCategory: String
    var newCategory: String
    var matchReasons: [RuleImpactMatchReasonSnapshot]
    var status: RuleImpactStatusSnapshot
    var reason: String?

    var id: Int64 {
        fileID
    }
}

struct RuleImpactConflictSnapshot: Equatable, Identifiable {
    var fileID: Int64
    var path: String?
    var conflictingPath: String?
    var kind: RuleImpactConflictKindSnapshot
    var reason: String

    var id: String {
        "\(fileID)-\(kind.rawValue)-\(conflictingPath ?? path ?? "none")"
    }
}

struct RuleImpactReportSnapshot: Equatable {
    var request: ClassifierImpactPreviewRequestSnapshot
    var affectedFileCount: Int64
    var willUpdateCount: Int64
    var alreadyCorrectCount: Int64
    var needsReviewCount: Int64
    var conflictCount: Int64
    var sampleLimit: Int64
    var samples: [RuleImpactSampleSnapshot]
    var conflicts: [RuleImpactConflictSnapshot]
    var needsReview: Bool
    var warningRequired: Bool
    var warning: String?
    var canApply: Bool
    var applyBlockedReason: String?
}

extension CoreBridge: CoreClassifierRuleSaving, CoreClassifierImpactPreviewing {
    func saveClassifierRule(repoPath: String, rule: ClassifierRuleSnapshot) async throws -> ClassifierRuleSnapshot {
        let saved = try await Task.detached(priority: .userInitiated) {
            try AreaMatrix.saveClassifierRule(repoPath: repoPath, rule: ClassifierRule(rule))
        }.value
        return ClassifierRuleSnapshot(coreRule: saved)
    }

    func previewClassifierRuleImpact(
        repoPath: String,
        request: ClassifierImpactPreviewRequestSnapshot
    ) async throws -> RuleImpactReportSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try RuleImpactReportSnapshot(coreReport: AreaMatrix.previewClassifierRuleImpact(
                repoPath: repoPath,
                request: ClassifierImpactPreviewRequest(request)
            ))
        }.value
    }
}

private extension ClassifierRule {
    init(_ snapshot: ClassifierRuleSnapshot) {
        self.init(
            targetCategory: snapshot.targetCategory,
            keywords: snapshot.keywords,
            extensions: snapshot.extensions,
            priority: snapshot.priority,
            previewConfirmed: snapshot.previewConfirmed
        )
    }
}

private extension ClassifierRuleSnapshot {
    init(coreRule: ClassifierRule) {
        targetCategory = coreRule.targetCategory
        keywords = coreRule.keywords
        extensions = coreRule.extensions
        priority = coreRule.priority
        previewConfirmed = coreRule.previewConfirmed
    }
}

private extension ClassifierImpactPreviewRequest {
    init(_ snapshot: ClassifierImpactPreviewRequestSnapshot) {
        self.init(
            mode: ClassifierImpactPreviewMode(snapshot.mode),
            rule: ClassifierRule(snapshot.rule),
            moveFiles: snapshot.moveFiles,
            replacementCategory: snapshot.replacementCategory
        )
    }
}

private extension ClassifierImpactPreviewMode {
    init(_ snapshot: ClassifierImpactPreviewModeSnapshot) {
        switch snapshot {
        case .ruleDraft: self = .ruleDraft
        case .removeKeyword: self = .removeKeyword
        case .removeExtension: self = .removeExtension
        case .removeCategory: self = .removeCategory
        }
    }
}

private extension ClassifierImpactPreviewRequestSnapshot {
    init(coreRequest: ClassifierImpactPreviewRequest) {
        mode = ClassifierImpactPreviewModeSnapshot(coreMode: coreRequest.mode)
        rule = ClassifierRuleSnapshot(coreRule: coreRequest.rule)
        moveFiles = coreRequest.moveFiles
        replacementCategory = coreRequest.replacementCategory
    }
}

private extension ClassifierImpactPreviewModeSnapshot {
    init(coreMode: ClassifierImpactPreviewMode) {
        switch coreMode {
        case .ruleDraft: self = .ruleDraft
        case .removeKeyword: self = .removeKeyword
        case .removeExtension: self = .removeExtension
        case .removeCategory: self = .removeCategory
        }
    }
}

private extension RuleImpactReportSnapshot {
    init(coreReport: RuleImpactReport) {
        request = ClassifierImpactPreviewRequestSnapshot(coreRequest: coreReport.request)
        affectedFileCount = coreReport.affectedFileCount
        willUpdateCount = coreReport.willUpdateCount
        alreadyCorrectCount = coreReport.alreadyCorrectCount
        needsReviewCount = coreReport.needsReviewCount
        conflictCount = coreReport.conflictCount
        sampleLimit = coreReport.sampleLimit
        samples = coreReport.samples.map(RuleImpactSampleSnapshot.init(coreSample:))
        conflicts = coreReport.conflicts.map(RuleImpactConflictSnapshot.init(coreConflict:))
        needsReview = coreReport.needsReview
        warningRequired = coreReport.warningRequired
        warning = coreReport.warning
        canApply = coreReport.canApply
        applyBlockedReason = coreReport.applyBlockedReason
    }
}

private extension RuleImpactSampleSnapshot {
    init(coreSample: RuleImpactSample) {
        fileID = coreSample.fileId
        path = coreSample.path
        currentCategory = coreSample.currentCategory
        newCategory = coreSample.newCategory
        matchReasons = coreSample.matchReasons.map(RuleImpactMatchReasonSnapshot.init(coreReason:))
        status = RuleImpactStatusSnapshot(coreStatus: coreSample.status)
        reason = coreSample.reason
    }
}

private extension RuleImpactMatchReasonSnapshot {
    init(coreReason: RuleImpactMatchReason) {
        switch coreReason {
        case .keyword: self = .keyword
        case .extension: self = .extension
        case .category: self = .category
        }
    }
}

private extension RuleImpactStatusSnapshot {
    init(coreStatus: RuleImpactStatus) {
        switch coreStatus {
        case .willUpdate: self = .willUpdate
        case .alreadyCorrect: self = .alreadyCorrect
        case .needsReview: self = .needsReview
        case .conflict: self = .conflict
        case .missing: self = .missing
        case .indexOnly: self = .indexOnly
        }
    }
}

private extension RuleImpactConflictSnapshot {
    init(coreConflict: RuleImpactConflict) {
        fileID = coreConflict.fileId
        path = coreConflict.path
        conflictingPath = coreConflict.conflictingPath
        kind = RuleImpactConflictKindSnapshot(coreKind: coreConflict.kind)
        reason = coreConflict.reason
    }
}

private extension RuleImpactConflictKindSnapshot {
    init(coreKind: RuleImpactConflictKind) {
        switch coreKind {
        case .nameConflict: self = .nameConflict
        case .missingFile: self = .missingFile
        case .unsupportedStorage: self = .unsupportedStorage
        case .ruleConflict: self = .ruleConflict
        }
    }
}
