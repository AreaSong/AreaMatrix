import Foundation

protocol CoreClassifierRuleEditing: Sendable {
    func listClassifierRules(
        repoPath: String,
        editingLocale: ClassifierEditingLocale?
    ) async throws -> ClassifierRuleEditorSnapshotState
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
    func createDefaultClassifier(
        repoPath: String,
        confirmed: Bool,
        editingLocale: ClassifierEditingLocale?
    ) async throws -> ClassifierRuleEditorSnapshotState
    func restoreDefaultClassifier(
        repoPath: String,
        confirmed: Bool,
        editingLocale: ClassifierEditingLocale?
    ) async throws -> ClassifierRuleEditorSnapshotState
    func restoreLastValidClassifier(
        repoPath: String,
        confirmed: Bool,
        editingLocale: ClassifierEditingLocale?
    ) async throws -> ClassifierRuleEditorSnapshotState
}

enum ClassifierEditingLocale: String, CaseIterable, Equatable, Identifiable {
    case zhHans = "zh-Hans"
    case en

    var id: String {
        rawValue
    }

    var coreValue: ContentLocale {
        switch self {
        case .zhHans: .zhHans
        case .en: .en
        }
    }

    init(coreValue: ContentLocale) {
        switch coreValue {
        case .zhHans: self = .zhHans
        case .en: self = .en
        }
    }
}

enum ClassifierConfigHealthState: Equatable {
    case valid
    case missing
    case unreadable
    case invalid

    init(coreValue: ClassifierConfigHealth) {
        switch coreValue {
        case .valid: self = .valid
        case .missing: self = .missing
        case .unreadable: self = .unreadable
        case .invalid: self = .invalid
        }
    }
}

enum ClassifierRecoveryActionState: Equatable, Identifiable {
    case createDefault
    case restoreDefault
    case restoreLastValid

    var id: String {
        switch self {
        case .createDefault: "create-default"
        case .restoreDefault: "restore-default"
        case .restoreLastValid: "restore-last-valid"
        }
    }

    init(coreValue: ClassifierRecoveryAction) {
        switch coreValue {
        case .createDefault: self = .createDefault
        case .restoreDefault: self = .restoreDefault
        case .restoreLastValid: self = .restoreLastValid
        }
    }
}

struct ClassifierRuleRecordSnapshot: Equatable, Identifiable {
    var ruleID: String
    var slug: String
    var displayNames: [String: String]
    var descriptions: [String: String]
    var extensions: [String]
    var keywords: [String]
    var priority: Int64
    var namingTemplate: String?
    var isDefault: Bool

    var id: String {
        ruleID
    }

    func displayName(for locale: ClassifierEditingLocale) -> String {
        displayNames[locale.rawValue] ?? ""
    }

    func description(for locale: ClassifierEditingLocale) -> String {
        descriptions[locale.rawValue] ?? ""
    }
}

struct ClassifierRuleEditorSnapshotState: Equatable {
    var rules: [ClassifierRuleRecordSnapshot]
    var defaultRuleID: String
    var updatedRuleID: String?
    var repositoryLocalePolicy: String
    var editingLocale: ClassifierEditingLocale?
    var health: ClassifierConfigHealthState
    var recoveryActions: [ClassifierRecoveryActionState]
    var warning: String?
}

struct ClassifierRuleCreateRequestSnapshot: Equatable {
    var repositoryLocalePolicy: String
    var editingLocale: ClassifierEditingLocale
    var slug: String
    var displayName: String
    var description: String
    var extensions: [String]
    var keywords: [String]
    var priority: Int64
    var namingTemplate: String?
}

struct ClassifierRuleUpdateSnapshot: Equatable {
    var repositoryLocalePolicy: String
    var editingLocale: ClassifierEditingLocale
    var ruleID: String
    var observed: ClassifierRuleObservedStateSnapshot
    var slug: String
    var displayName: String
    var description: String
    var extensions: [String]
    var keywords: [String]
    var priority: Int64
    var namingTemplate: String?
    var previewConfirmed: Bool
}

struct ClassifierRuleObservedStateSnapshot: Equatable {
    var ruleID: String
    var slug: String
    var displayName: String
    var description: String
    var extensions: [String]
    var keywords: [String]
    var priority: Int64
    var namingTemplate: String?
}

struct ClassifierRuleDeleteRequestSnapshot: Equatable {
    var ruleID: String
    var replacementCategory: String?
    var previewConfirmed: Bool
}

extension CoreBridge: CoreClassifierRuleEditing {
    func listClassifierRules(
        repoPath: String,
        editingLocale: ClassifierEditingLocale?
    ) async throws -> ClassifierRuleEditorSnapshotState {
        try await Task.detached(priority: .userInitiated) {
            try ClassifierRuleEditorSnapshotState(coreSnapshot: AreaMatrix.listClassifierRules(
                repoPath: repoPath,
                editingLocale: editingLocale?.coreValue
            ))
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

    func createDefaultClassifier(
        repoPath: String,
        confirmed: Bool,
        editingLocale: ClassifierEditingLocale?
    ) async throws -> ClassifierRuleEditorSnapshotState {
        try await Task.detached(priority: .userInitiated) {
            try ClassifierRuleEditorSnapshotState(coreSnapshot: AreaMatrix.createDefaultClassifier(
                repoPath: repoPath,
                confirmed: confirmed,
                editingLocale: editingLocale?.coreValue
            ))
        }.value
    }

    func restoreDefaultClassifier(
        repoPath: String,
        confirmed: Bool,
        editingLocale: ClassifierEditingLocale?
    ) async throws -> ClassifierRuleEditorSnapshotState {
        try await Task.detached(priority: .userInitiated) {
            try ClassifierRuleEditorSnapshotState(coreSnapshot: AreaMatrix.restoreDefaultClassifier(
                repoPath: repoPath,
                confirmed: confirmed,
                editingLocale: editingLocale?.coreValue
            ))
        }.value
    }

    func restoreLastValidClassifier(
        repoPath: String,
        confirmed: Bool,
        editingLocale: ClassifierEditingLocale?
    ) async throws -> ClassifierRuleEditorSnapshotState {
        try await Task.detached(priority: .userInitiated) {
            try ClassifierRuleEditorSnapshotState(coreSnapshot: AreaMatrix.restoreLastValidClassifier(
                repoPath: repoPath,
                confirmed: confirmed,
                editingLocale: editingLocale?.coreValue
            ))
        }.value
    }
}

private extension ClassifierRuleEditorSnapshotState {
    init(coreSnapshot: ClassifierRuleEditorSnapshot) {
        rules = coreSnapshot.rules.map(ClassifierRuleRecordSnapshot.init(coreRule:))
        defaultRuleID = coreSnapshot.defaultRuleId
        updatedRuleID = coreSnapshot.updatedRuleId
        repositoryLocalePolicy = coreSnapshot.repositoryLocalePolicy
        editingLocale = coreSnapshot.editingLocale.map(ClassifierEditingLocale.init(coreValue:))
        health = ClassifierConfigHealthState(coreValue: coreSnapshot.health)
        recoveryActions = coreSnapshot.recoveryActions.map(ClassifierRecoveryActionState.init(coreValue:))
        warning = coreSnapshot.warning
    }
}

private extension ClassifierRuleRecordSnapshot {
    init(coreRule: ClassifierRuleRecord) {
        ruleID = coreRule.ruleId
        slug = coreRule.slug
        displayNames = Self.localeMap(coreRule.displayNames)
        descriptions = Self.localeMap(coreRule.descriptions)
        extensions = coreRule.extensions
        keywords = coreRule.keywords
        priority = coreRule.priority
        namingTemplate = coreRule.namingTemplate
        isDefault = coreRule.isDefault
    }

    private static func localeMap(_ values: [ClassifierLocaleValue]) -> [String: String] {
        values.reduce(into: [:]) { result, item in
            result[item.locale] = item.value
        }
    }
}

private extension ClassifierRuleCreateRequest {
    init(_ snapshot: ClassifierRuleCreateRequestSnapshot) {
        self.init(
            repositoryLocalePolicy: snapshot.repositoryLocalePolicy,
            editingLocale: snapshot.editingLocale.coreValue,
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
            repositoryLocalePolicy: snapshot.repositoryLocalePolicy,
            editingLocale: snapshot.editingLocale.coreValue,
            ruleId: snapshot.ruleID,
            observed: ClassifierRuleObservedState(snapshot.observed),
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

private extension ClassifierRuleObservedState {
    init(_ snapshot: ClassifierRuleObservedStateSnapshot) {
        self.init(
            ruleId: snapshot.ruleID,
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

private extension ClassifierRuleDeleteRequest {
    init(_ snapshot: ClassifierRuleDeleteRequestSnapshot) {
        self.init(
            ruleId: snapshot.ruleID,
            replacementCategory: snapshot.replacementCategory,
            previewConfirmed: snapshot.previewConfirmed
        )
    }
}
