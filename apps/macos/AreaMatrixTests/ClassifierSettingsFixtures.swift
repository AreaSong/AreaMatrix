@testable import AreaMatrix

extension CoreErrorMappingSnapshot {
    static func classifierSettingsMapping(
        kind: CoreErrorKindSnapshot,
        userMessage: String
    ) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: kind,
            userMessage: userMessage,
            suggestedAction: "Retry save",
            rawContext: kind.rawValue
        )
    }

    static func classifierRecoveryMapping(
        kind: CoreErrorKindSnapshot,
        userMessage: String
    ) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: kind,
            userMessage: userMessage,
            suggestedAction: "Open classifier.yaml",
            recoverability: .userActionRequired,
            rawContext: kind.rawValue
        )
    }
}

extension AppRepoConfigSnapshot {
    static func classifierSettingsFixture(
        repoPath: String,
        enableExtensionRules: Bool = true,
        enableKeywordRules: Bool = true,
        fallbackToInbox: Bool = true
    ) -> AppRepoConfigSnapshot {
        AppRepoConfigSnapshot.testFixture(repoPath: repoPath) {
            $0.locale = "system"
            $0.enableExtensionRules = enableExtensionRules
            $0.enableKeywordRules = enableKeywordRules
            $0.fallbackToInbox = fallbackToInbox
        }
    }

    static func classifierRecoveryFixture(repoPath: String) -> AppRepoConfigSnapshot {
        AppRepoConfigSnapshot.testFixture(repoPath: repoPath) {
            $0.locale = "en"
        }
    }
}

extension ClassifierRuleEditorSnapshotState {
    static func classifierEditorFixture(updatedRuleID: String? = nil) -> ClassifierRuleEditorSnapshotState {
        ClassifierRuleEditorSnapshotState(
            rules: [
                ClassifierRuleRecordSnapshot.testFixture(
                    ruleID: "docs",
                    displayName: "Documents",
                    isDefault: true
                ) {
                    $0.descriptions[ClassifierEditingLocale.en.rawValue] = "Docs"
                    $0.extensions = ["md"]
                    $0.keywords = ["report"]
                },
                ClassifierRuleRecordSnapshot.testFixture(
                    ruleID: "finance",
                    displayName: "Finance"
                ) {
                    $0.descriptions[ClassifierEditingLocale.en.rawValue] = "Finance docs"
                    $0.extensions = ["pdf"]
                    $0.priority = 10
                }
            ],
            defaultRuleID: "docs",
            updatedRuleID: updatedRuleID,
            repositoryLocalePolicy: "system",
            editingLocale: .en,
            health: .valid,
            recoveryActions: [],
            warning: nil
        )
    }

    static func classifierDegradedFixture(
        health: ClassifierConfigHealthState,
        recoveryActions: [ClassifierRecoveryActionState],
        warning: String = "classifier unavailable"
    ) -> ClassifierRuleEditorSnapshotState {
        ClassifierRuleEditorSnapshotState(
            rules: [],
            defaultRuleID: "",
            updatedRuleID: nil,
            repositoryLocalePolicy: "system",
            editingLocale: nil,
            health: health,
            recoveryActions: recoveryActions,
            warning: warning
        )
    }
}

extension ClassifierRuleRecordSnapshot {
    static func testFixture(
        ruleID: String,
        slug: String? = nil,
        displayName: String? = nil,
        isDefault: Bool = false,
        configure: (inout ClassifierRuleRecordSnapshot) -> Void = { _ in }
    ) -> ClassifierRuleRecordSnapshot {
        var snapshot = ClassifierRuleRecordSnapshot(
            ruleID: ruleID,
            slug: slug ?? ruleID,
            displayNames: [ClassifierEditingLocale.en.rawValue: displayName ?? ruleID],
            descriptions: [:],
            extensions: [],
            keywords: [],
            priority: 0,
            namingTemplate: nil,
            isDefault: isDefault
        )
        configure(&snapshot)
        return snapshot
    }
}

extension ClassifierRuleDraftSnapshot {
    static func testFixture(
        sourceFileID: Int64 = 260,
        targetCategory: String = "finance",
        keywordCandidates: [String] = ["client-a", "contract"],
        extensionCandidates: [String] = ["pdf"],
        priority: Int64 = 42
    ) -> ClassifierRuleDraftSnapshot {
        ClassifierRuleDraftSnapshot(
            sourceFileID: sourceFileID,
            targetCategory: targetCategory,
            keywordCandidates: keywordCandidates,
            extensionCandidates: extensionCandidates,
            priority: priority
        )
    }
}

extension ClassifierRuleSnapshot {
    static func testFixture(
        targetCategory: String = "finance",
        keywords: [String] = ["contract"],
        extensions: [String] = [],
        priority: Int64 = 0,
        previewConfirmed: Bool = false
    ) -> ClassifierRuleSnapshot {
        ClassifierRuleSnapshot(
            targetCategory: targetCategory,
            keywords: keywords,
            extensions: extensions,
            priority: priority,
            previewConfirmed: previewConfirmed
        )
    }
}

func classifierSettingsValidationProbeResult() -> ClassifyResultSnapshot {
    .testFixture(
        category: "inbox",
        suggestedName: "AreaMatrixValidationProbe.txt",
        reason: .default,
        confidence: 0
    )
}
