import Foundation

protocol CoreFileCategoryMoving: Sendable {
    func previewMoveToCategory(
        repoPath: String,
        fileID: Int64,
        newCategory: String
    ) async throws -> MoveToCategoryPreviewSnapshot

    func moveToCategory(repoPath: String, fileID: Int64, newCategory: String) async throws -> FileEntrySnapshot

    func correctFileCategory(
        repoPath: String,
        fileID: Int64,
        targetCategory: String,
        moveFile: Bool,
        remember: Bool
    ) async throws -> ClassifierCorrectionResultSnapshot
}

protocol CoreClassifierRuleSaving: Sendable {
    func saveClassifierRule(repoPath: String, rule: ClassifierRuleSnapshot) async throws -> ClassifierRuleSnapshot
}

protocol CoreClassifierImpactPreviewing: Sendable {
    func previewClassifierRuleImpact(
        repoPath: String,
        request: ClassifierImpactPreviewRequestSnapshot
    ) async throws -> RuleImpactReportSnapshot
}

extension CoreFileCategoryMoving {
    func correctFileCategory(
        repoPath _: String,
        fileID _: Int64,
        targetCategory _: String,
        moveFile _: Bool,
        remember _: Bool
    ) async throws -> ClassifierCorrectionResultSnapshot {
        throw CoreError.Internal(message: "correct_file_category is unavailable")
    }
}

struct MoveToCategoryPreviewSnapshot: Equatable {
    var fileID: Int64
    var fromCategory: String
    var toCategory: String
    var currentPath: String
    var targetPath: String
    var targetName: String
    var storageMode: String
    var indexOnly: Bool
    var nameConflictResolved: Bool
    var willMoveFile: Bool
}

struct ClassifierRuleDraftSnapshot: Equatable {
    var sourceFileID: Int64
    var targetCategory: String
    var keywordCandidates: [String]
    var extensionCandidates: [String]
    var priority: Int64
}

struct ClassifierCorrectionResultSnapshot: Equatable {
    var updatedFile: FileEntrySnapshot
    var ruleDraft: ClassifierRuleDraftSnapshot?
    var moveFileRequested: Bool
    var rememberRequested: Bool
    var ruleConfirmationRequired: Bool
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
        case .keyword: "Keyword"
        case .extension: "Extension"
        case .category: "Category"
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

    var id: Int64 { fileID }
}

struct RuleImpactConflictSnapshot: Equatable, Identifiable {
    var fileID: Int64
    var path: String?
    var conflictingPath: String?
    var kind: RuleImpactConflictKindSnapshot
    var reason: String

    var id: String { "\(fileID)-\(kind.rawValue)-\(conflictingPath ?? path ?? "none")" }
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

extension MoveToCategoryPreviewSnapshot {
    init(corePreview: MoveToCategoryPreview) {
        fileID = corePreview.fileId
        fromCategory = corePreview.fromCategory
        toCategory = corePreview.toCategory
        currentPath = corePreview.currentPath
        targetPath = corePreview.targetPath
        targetName = corePreview.targetName
        storageMode = corePreview.storageMode.moveToCategoryDisplayName
        indexOnly = corePreview.indexOnly
        nameConflictResolved = corePreview.nameConflictResolved
        willMoveFile = corePreview.willMoveFile
    }
}

extension CoreBridge: CoreFileCategoryMoving, CoreClassifierRuleSaving, CoreClassifierImpactPreviewing {
    func previewMoveToCategory(
        repoPath: String,
        fileID: Int64,
        newCategory: String
    ) async throws -> MoveToCategoryPreviewSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try MoveToCategoryPreviewSnapshot(corePreview: previewCoreMoveToCategory(
                repoPath: repoPath,
                fileID: fileID,
                newCategory: newCategory
            ))
        }.value
    }

    func moveToCategory(repoPath: String, fileID: Int64, newCategory: String) async throws -> FileEntrySnapshot {
        let entry = try await Task.detached(priority: .userInitiated) {
            try moveCoreToCategory(repoPath: repoPath, fileID: fileID, newCategory: newCategory)
        }.value
        return await makeFileEntrySnapshot(from: entry, repoPath: repoPath)
    }

    func correctFileCategory(
        repoPath: String,
        fileID: Int64,
        targetCategory: String,
        moveFile: Bool,
        remember: Bool
    ) async throws -> ClassifierCorrectionResultSnapshot {
        let result = try await Task.detached(priority: .userInitiated) {
            try AreaMatrix.correctFileCategory(
                repoPath: repoPath,
                fileId: fileID,
                category: targetCategory,
                moveFile: moveFile,
                remember: remember
            )
        }.value
        let updatedFile = await makeFileEntrySnapshot(from: result.updatedFile, repoPath: repoPath)
        return ClassifierCorrectionResultSnapshot(coreResult: result, updatedFile: updatedFile)
    }

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

private func previewCoreMoveToCategory(
    repoPath: String,
    fileID: Int64,
    newCategory: String
) throws -> MoveToCategoryPreview {
    try previewMoveToCategory(repoPath: repoPath, fileId: fileID, newCategory: newCategory)
}

private func moveCoreToCategory(repoPath: String, fileID: Int64, newCategory: String) throws -> FileEntry {
    try moveToCategory(repoPath: repoPath, fileId: fileID, newCategory: newCategory)
}

private extension StorageMode {
    var moveToCategoryDisplayName: String {
        switch self {
        case .moved:
            "Moved"
        case .copied:
            "Copied"
        case .indexed:
            "Indexed"
        }
    }
}

private extension ClassifierCorrectionResultSnapshot {
    init(coreResult: ClassifierCorrectionResult, updatedFile: FileEntrySnapshot) {
        self.updatedFile = updatedFile
        ruleDraft = coreResult.ruleDraft.map(ClassifierRuleDraftSnapshot.init(coreDraft:))
        moveFileRequested = coreResult.moveFileRequested
        rememberRequested = coreResult.rememberRequested
        ruleConfirmationRequired = coreResult.ruleConfirmationRequired
    }
}

private extension ClassifierRuleDraftSnapshot {
    init(coreDraft: ClassifierRuleDraft) {
        sourceFileID = coreDraft.sourceFileId
        targetCategory = coreDraft.targetCategory
        keywordCandidates = coreDraft.keywordCandidates
        extensionCandidates = coreDraft.extensionCandidates
        priority = coreDraft.priority
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
