import Foundation

protocol CoreClassifierRuleEditing: Sendable {
    func listClassifierRules(repoPath: String) async throws -> ClassifierRuleEditorSnapshotState
    func createClassifierRule(
        repoPath: String,
        request: ClassifierRuleCreateRequestSnapshot
    ) async throws -> ClassifierRuleEditorSnapshotState
    func updateClassifierRule(
        repoPath: String,
        request: ClassifierRuleUpdateSnapshot
    ) async throws -> ClassifierRuleEditorSnapshotState
    func deleteClassifierRule(
        repoPath: String,
        request: ClassifierRuleDeleteRequestSnapshot
    ) async throws -> ClassifierRuleEditorSnapshotState
}

struct ClassifierRuleRecordSnapshot: Equatable, Identifiable {
    var ruleID: String
    var slug: String
    var displayName: String
    var description: String
    var extensions: [String]
    var keywords: [String]
    var priority: Int64
    var namingTemplate: String?
    var isDefault: Bool

    var id: String {
        ruleID
    }
}

struct ClassifierRuleEditorSnapshotState: Equatable {
    var rules: [ClassifierRuleRecordSnapshot]
    var defaultRuleID: String
    var updatedRuleID: String?
    var warning: String?
}

struct ClassifierRuleCreateRequestSnapshot: Equatable {
    var slug: String
    var displayName: String
    var description: String
    var extensions: [String]
    var keywords: [String]
    var priority: Int64
    var namingTemplate: String?
}

struct ClassifierRuleUpdateSnapshot: Equatable {
    var ruleID: String
    var slug: String
    var displayName: String
    var description: String
    var extensions: [String]
    var keywords: [String]
    var priority: Int64
    var namingTemplate: String?
    var previewConfirmed: Bool
}

struct ClassifierRuleDeleteRequestSnapshot: Equatable {
    var ruleID: String
    var replacementCategory: String?
    var previewConfirmed: Bool
}

extension CoreBridge: CoreClassifierRuleEditing {
    func listClassifierRules(repoPath: String) async throws -> ClassifierRuleEditorSnapshotState {
        try await Task.detached(priority: .userInitiated) {
            try ClassifierRuleEditorSnapshotState(coreSnapshot: AreaMatrix.listClassifierRules(repoPath: repoPath))
        }.value
    }

    func createClassifierRule(
        repoPath: String,
        request: ClassifierRuleCreateRequestSnapshot
    ) async throws -> ClassifierRuleEditorSnapshotState {
        try await Task.detached(priority: .userInitiated) {
            try ClassifierRuleEditorSnapshotState(coreSnapshot: AreaMatrix.createClassifierRule(
                repoPath: repoPath,
                request: ClassifierRuleCreateRequest(request)
            ))
        }.value
    }

    func updateClassifierRule(
        repoPath: String,
        request: ClassifierRuleUpdateSnapshot
    ) async throws -> ClassifierRuleEditorSnapshotState {
        try await Task.detached(priority: .userInitiated) {
            try ClassifierRuleEditorSnapshotState(coreSnapshot: AreaMatrix.updateClassifierRule(
                repoPath: repoPath,
                request: ClassifierRuleUpdate(request)
            ))
        }.value
    }

    func deleteClassifierRule(
        repoPath: String,
        request: ClassifierRuleDeleteRequestSnapshot
    ) async throws -> ClassifierRuleEditorSnapshotState {
        try await Task.detached(priority: .userInitiated) {
            try ClassifierRuleEditorSnapshotState(coreSnapshot: AreaMatrix.deleteClassifierRule(
                repoPath: repoPath,
                request: ClassifierRuleDeleteRequest(request)
            ))
        }.value
    }
}

private extension ClassifierRuleEditorSnapshotState {
    init(coreSnapshot: ClassifierRuleEditorSnapshot) {
        rules = coreSnapshot.rules.map(ClassifierRuleRecordSnapshot.init(coreRule:))
        defaultRuleID = coreSnapshot.defaultRuleId
        updatedRuleID = coreSnapshot.updatedRuleId
        warning = coreSnapshot.warning
    }
}

private extension ClassifierRuleRecordSnapshot {
    init(coreRule: ClassifierRuleRecord) {
        ruleID = coreRule.ruleId
        slug = coreRule.slug
        displayName = coreRule.displayName
        description = coreRule.description
        extensions = coreRule.extensions
        keywords = coreRule.keywords
        priority = coreRule.priority
        namingTemplate = coreRule.namingTemplate
        isDefault = coreRule.isDefault
    }
}

private extension ClassifierRuleCreateRequest {
    init(_ snapshot: ClassifierRuleCreateRequestSnapshot) {
        self.init(
            slug: snapshot.slug,
            displayName: snapshot.displayName,
            description: snapshot.description,
            extensions: snapshot.extensions,
            keywords: snapshot.keywords,
            priority: snapshot.priority,
            namingTemplate: snapshot.namingTemplate
        )
    }
}

private extension ClassifierRuleUpdate {
    init(_ snapshot: ClassifierRuleUpdateSnapshot) {
        self.init(
            ruleId: snapshot.ruleID,
            slug: snapshot.slug,
            displayName: snapshot.displayName,
            description: snapshot.description,
            extensions: snapshot.extensions,
            keywords: snapshot.keywords,
            priority: snapshot.priority,
            namingTemplate: snapshot.namingTemplate,
            previewConfirmed: snapshot.previewConfirmed
        )
    }
}

private extension ClassifierRuleDeleteRequest {
    init(_ snapshot: ClassifierRuleDeleteRequestSnapshot) {
        self.init(
            ruleId: snapshot.ruleID,
            replacementCategory: snapshot.replacementCategory,
            previewConfirmed: snapshot.previewConfirmed
        )
    }
}
