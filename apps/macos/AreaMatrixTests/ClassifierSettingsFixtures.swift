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

extension RepoConfigSnapshot {
    static func classifierSettingsFixture(
        repoPath: String,
        enableExtensionRules: Bool = true,
        enableKeywordRules: Bool = true,
        fallbackToInbox: Bool = true
    ) -> RepoConfigSnapshot {
        RepoConfigSnapshot.testFixture(repoPath: repoPath) {
            $0.locale = "system"
            $0.enableExtensionRules = enableExtensionRules
            $0.enableKeywordRules = enableKeywordRules
            $0.fallbackToInbox = fallbackToInbox
        }
    }

    static func classifierRecoveryFixture(repoPath: String) -> RepoConfigSnapshot {
        RepoConfigSnapshot.testFixture(repoPath: repoPath) {
            $0.locale = "system"
        }
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
    .testFixture(
        category: "inbox",
        suggestedName: "AreaMatrixValidationProbe.txt",
        reason: .default,
        confidence: 0
    )
}
