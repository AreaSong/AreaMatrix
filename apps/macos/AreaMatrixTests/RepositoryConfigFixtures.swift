@testable import AreaMatrix

struct RepoConfigTestFixtureOptions {
    var defaultMode = "Copied"
    var overviewOutput = "GeneratedOnly"
    var aiEnabled = false
    var locale = "zh-Hans"
    var iCloudWarn = true
    var enableExtensionRules = true
    var enableKeywordRules = true
    var fallbackToInbox = true
    var allowReplaceDuringImport = false
}

extension RepoConfigSnapshot {
    static func testFixture(
        repoPath: String,
        options configure: (inout RepoConfigTestFixtureOptions) -> Void = { _ in }
    ) -> RepoConfigSnapshot {
        var options = RepoConfigTestFixtureOptions()
        configure(&options)

        return RepoConfigSnapshot(
            repoPath: repoPath,
            defaultMode: options.defaultMode,
            overviewOutput: options.overviewOutput,
            aiEnabled: options.aiEnabled,
            locale: options.locale,
            iCloudWarn: options.iCloudWarn,
            enableExtensionRules: options.enableExtensionRules,
            enableKeywordRules: options.enableKeywordRules,
            fallbackToInbox: options.fallbackToInbox,
            allowReplaceDuringImport: options.allowReplaceDuringImport
        )
    }

    static func generalSettingsFixture(
        repoPath: String,
        defaultMode: String = "Copied",
        overviewOutput: String = "GeneratedOnly",
        locale: String = "system"
    ) -> RepoConfigSnapshot {
        RepoConfigSnapshot.testFixture(repoPath: repoPath) {
            $0.defaultMode = defaultMode
            $0.overviewOutput = overviewOutput
            $0.locale = locale
        }
    }

    static func advancedSettingsFixture(
        repoPath: String,
        overviewOutput: String = "GeneratedOnly",
        allowReplaceDuringImport: Bool = false
    ) -> RepoConfigSnapshot {
        RepoConfigSnapshot.testFixture(repoPath: repoPath) {
            $0.overviewOutput = overviewOutput
            $0.locale = "system"
            $0.allowReplaceDuringImport = allowReplaceDuringImport
        }
    }

    static func integrationsFixture(repoPath: String, iCloudWarn: Bool = true) -> RepoConfigSnapshot {
        RepoConfigSnapshot.testFixture(repoPath: repoPath) {
            $0.locale = "system"
            $0.iCloudWarn = iCloudWarn
        }
    }
}
