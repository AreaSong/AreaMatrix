@testable import AreaMatrix

extension RepoConfigSnapshot {
    static func generalSettingsFixture(
        repoPath: String,
        defaultMode: String = "Copied",
        overviewOutput: String = "GeneratedOnly",
        locale: String = "system"
    ) -> RepoConfigSnapshot {
        RepoConfigSnapshot(
            repoPath: repoPath,
            defaultMode: defaultMode,
            overviewOutput: overviewOutput,
            aiEnabled: false,
            locale: locale,
            iCloudWarn: true,
            enableExtensionRules: true,
            enableKeywordRules: true,
            fallbackToInbox: true,
            allowReplaceDuringImport: false
        )
    }

    static func advancedSettingsFixture(
        repoPath: String,
        overviewOutput: String = "GeneratedOnly",
        allowReplaceDuringImport: Bool = false
    ) -> RepoConfigSnapshot {
        RepoConfigSnapshot(
            repoPath: repoPath,
            defaultMode: "Copied",
            overviewOutput: overviewOutput,
            aiEnabled: false,
            locale: "system",
            iCloudWarn: true,
            enableExtensionRules: true,
            enableKeywordRules: true,
            fallbackToInbox: true,
            allowReplaceDuringImport: allowReplaceDuringImport
        )
    }

    static func integrationsFixture(repoPath: String, iCloudWarn: Bool = true) -> RepoConfigSnapshot {
        RepoConfigSnapshot(
            repoPath: repoPath,
            defaultMode: "Copied",
            overviewOutput: "GeneratedOnly",
            aiEnabled: false,
            locale: "system",
            iCloudWarn: iCloudWarn,
            enableExtensionRules: true,
            enableKeywordRules: true,
            fallbackToInbox: true,
            allowReplaceDuringImport: false
        )
    }
}
