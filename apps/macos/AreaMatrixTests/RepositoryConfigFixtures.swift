@testable import AreaMatrix

struct RepoConfigTestFixtureOptions {
    var revision: Int64 = 0
    var defaultMode = "Copied"
    var overviewOutput = "GeneratedOnly"
    var aiEnabled = false
    var locale = "system"
    var iCloudWarn = true
    var enableExtensionRules = true
    var enableKeywordRules = true
    var fallbackToInbox = true
    var allowReplaceDuringImport = false
}

extension AppRepoConfigSnapshot {
    static func testFixture(
        repoPath: String,
        options configure: (inout RepoConfigTestFixtureOptions) -> Void = { _ in }
    ) -> AppRepoConfigSnapshot {
        var options = RepoConfigTestFixtureOptions()
        configure(&options)

        return AppRepoConfigSnapshot(
            repoPath: repoPath,
            revision: options.revision,
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
    ) -> AppRepoConfigSnapshot {
        AppRepoConfigSnapshot.testFixture(repoPath: repoPath) {
            $0.defaultMode = defaultMode
            $0.overviewOutput = overviewOutput
            $0.locale = locale
        }
    }

    static func advancedSettingsFixture(
        repoPath: String,
        overviewOutput: String = "GeneratedOnly",
        allowReplaceDuringImport: Bool = false
    ) -> AppRepoConfigSnapshot {
        AppRepoConfigSnapshot.testFixture(repoPath: repoPath) {
            $0.overviewOutput = overviewOutput
            $0.locale = "system"
            $0.allowReplaceDuringImport = allowReplaceDuringImport
        }
    }

    static func integrationsFixture(repoPath: String, iCloudWarn: Bool = true) -> AppRepoConfigSnapshot {
        AppRepoConfigSnapshot.testFixture(repoPath: repoPath) {
            $0.locale = "system"
            $0.iCloudWarn = iCloudWarn
        }
    }
}
