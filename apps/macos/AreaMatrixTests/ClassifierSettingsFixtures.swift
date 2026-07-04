@testable import AreaMatrix

extension CoreErrorMappingSnapshot {
    static func classifierSettingsMapping(
        kind: CoreErrorKindSnapshot,
        userMessage: String
    ) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: kind,
            userMessage: userMessage,
            severity: .medium,
            suggestedAction: "Retry save",
            recoverability: .retryable,
            rawContext: kind.rawValue
        )
    }

    static func classifierRecoveryMapping(
        kind: CoreErrorKindSnapshot,
        userMessage: String
    ) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: kind,
            userMessage: userMessage,
            severity: .medium,
            suggestedAction: "Open classifier.yaml",
            recoverability: .userActionRequired,
            rawContext: kind.rawValue
        )
    }
}

extension RepoConfigSnapshot {
    static func classifierSettingsFixture(
        repoPath: String,
        enableExtensionRules: Bool = true,
        enableKeywordRules: Bool = true,
        fallbackToInbox: Bool = true
    ) -> RepoConfigSnapshot {
        RepoConfigSnapshot(
            repoPath: repoPath,
            defaultMode: "Copied",
            overviewOutput: "GeneratedOnly",
            aiEnabled: false,
            locale: "system",
            iCloudWarn: true,
            enableExtensionRules: enableExtensionRules,
            enableKeywordRules: enableKeywordRules,
            fallbackToInbox: fallbackToInbox,
            allowReplaceDuringImport: false
        )
    }

    static func classifierRecoveryFixture(repoPath: String) -> RepoConfigSnapshot {
        RepoConfigSnapshot(
            repoPath: repoPath,
            defaultMode: "Copied",
            overviewOutput: "GeneratedOnly",
            aiEnabled: false,
            locale: "system",
            iCloudWarn: true,
            enableExtensionRules: true,
            enableKeywordRules: true,
            fallbackToInbox: true,
            allowReplaceDuringImport: false
        )
    }
}

extension ClassifierRuleEditorSnapshotState {
    static func classifierEditorFixture(updatedRuleID: String? = nil) -> ClassifierRuleEditorSnapshotState {
        ClassifierRuleEditorSnapshotState(
            rules: [
                ClassifierRuleRecordSnapshot(
                    ruleID: "docs",
                    slug: "docs",
                    displayName: "Documents",
                    description: "Docs",
                    extensions: ["md"],
                    keywords: ["report"],
                    priority: 0,
                    namingTemplate: nil,
                    isDefault: true
                ),
                ClassifierRuleRecordSnapshot(
                    ruleID: "finance",
                    slug: "finance",
                    displayName: "Finance",
                    description: "Finance docs",
                    extensions: ["pdf"],
                    keywords: [],
                    priority: 10,
                    namingTemplate: nil,
                    isDefault: false
                )
            ],
            defaultRuleID: "docs",
            updatedRuleID: updatedRuleID,
            warning: nil
        )
    }
}

func classifierSettingsValidationProbeResult() -> ClassifyResultSnapshot {
    ClassifyResultSnapshot(
        category: "inbox",
        suggestedName: "AreaMatrixValidationProbe.txt",
        reason: .default,
        confidence: 0
    )
}
