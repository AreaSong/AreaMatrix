@testable import AreaMatrix
import XCTest

final class RepositorySettingsConfigPageFeatureTests: XCTestCase {
    @MainActor
    func testRepositorySettingsCrossPlatformRepositorySettingsCoreSavesRepositoryConfigThroughUpdateConfig() async {
        let current = RepoConfigSnapshot.repositorySettingsRepositorySettingsCoreFixture(repoPath: "/tmp/repo")
        let updater = RepositorySettingsRecordingUpdater(result: .success)
        let announcer = RecordingAccessibilityAnnouncer()
        let model = RepositorySettingsConfigModel(
            repoPath: "/tmp/repo",
            updater: updater,
            errorMapper: RepositorySettingsStaticErrorMapper(),
            accessibilityAnnouncer: announcer
        )
        var draft = RepositorySettingsConfigDraft(config: current)
        draft.overviewOutput = .rootAreaMatrixFile
        draft.locale = .en
        draft.iCloudWarn = false
        draft.fallbackToInbox = false

        let didSave = await model.save(draft: draft, currentConfig: current)
        let requests = await updater.requests()

        XCTAssertTrue(didSave)
        XCTAssertEqual(requests, [RepositorySettingsRecordingUpdater.Request(
            repoPath: "/tmp/repo",
            config: current
                .withRepositorySettingsRepositorySettingsCoreOverviewOutput("RootAreaMatrixFile")
                .withRepositorySettingsRepositorySettingsCoreLocale("en")
                .withRepositorySettingsRepositorySettingsCoreICloudWarn(false)
                .withRepositorySettingsRepositorySettingsCoreFallbackToInbox(false)
        )])
        XCTAssertEqual(model.saveState, .saved("Repository settings saved."))
        XCTAssertEqual(announcer.announcements, ["Repository settings saved."])
    }

    @MainActor
    func testRepositorySettingsCrossPlatformRepositorySettingsCoreSaveFailureMapsCoreErrorAndKeepsPayloadObservable(
    ) async {
        let current = RepoConfigSnapshot.repositorySettingsRepositorySettingsCoreFixture(repoPath: "/tmp/repo")
        let updater =
            RepositorySettingsRecordingUpdater(result: .failure(CoreError.PermissionDenied(path: "/tmp/repo")))
        let mapper = RepositorySettingsStaticErrorMapper()
        let announcer = RecordingAccessibilityAnnouncer()
        let model = RepositorySettingsConfigModel(
            repoPath: "/tmp/repo",
            updater: updater,
            errorMapper: mapper,
            accessibilityAnnouncer: announcer
        )
        var draft = RepositorySettingsConfigDraft(config: current)
        draft.locale = .zhCN

        let didSave = await model.save(draft: draft, currentConfig: current)
        let requests = await updater.requests()
        let mappedErrors = await mapper.mappedErrors()

        XCTAssertFalse(didSave)
        XCTAssertEqual(requests.map(\.config.locale), ["zh-CN"])
        XCTAssertEqual(mappedErrors, [CoreError.PermissionDenied(path: "/tmp/repo")])
        XCTAssertEqual(model.saveState, .failed(RepositorySettingsConfigError(
            message: "权限错误",
            recovery: "Retry status"
        )))
        XCTAssertEqual(announcer.announcements, ["Repository settings could not be saved."])
    }
}

private extension RepoConfigSnapshot {
    static func repositorySettingsRepositorySettingsCoreFixture(repoPath: String) -> RepoConfigSnapshot {
        RepoConfigSnapshot(
            repoPath: repoPath,
            defaultMode: "Copied",
            overviewOutput: "GeneratedOnly",
            aiEnabled: true,
            locale: "zh-Hans",
            iCloudWarn: true,
            enableExtensionRules: true,
            enableKeywordRules: true,
            fallbackToInbox: true,
            allowReplaceDuringImport: false
        )
    }

    func withRepositorySettingsRepositorySettingsCoreOverviewOutput(_ value: String) -> RepoConfigSnapshot {
        var config = self
        config.overviewOutput = value
        return config
    }

    func withRepositorySettingsRepositorySettingsCoreLocale(_ value: String) -> RepoConfigSnapshot {
        var config = self
        config.locale = value
        return config
    }

    func withRepositorySettingsRepositorySettingsCoreICloudWarn(_ value: Bool) -> RepoConfigSnapshot {
        var config = self
        config.iCloudWarn = value
        return config
    }

    func withRepositorySettingsRepositorySettingsCoreFallbackToInbox(_ value: Bool) -> RepoConfigSnapshot {
        var config = self
        config.fallbackToInbox = value
        return config
    }
}
