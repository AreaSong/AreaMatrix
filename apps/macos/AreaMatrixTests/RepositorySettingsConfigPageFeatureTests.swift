@testable import AreaMatrix
import XCTest

final class RepositorySettingsConfigPageFeatureTests: XCTestCase {
    @MainActor
    func testRepositorySettingsCrossPlatformRepositorySettingsCoreSavesRepositoryConfigThroughUpdateConfig() async {
        let current = RepoConfigSnapshot.repositorySettingsConfigFixture(repoPath: "/tmp/repo")
        let updater = RecordingConfigurationUpdater(result: .success(()))
        let announcer = RecordingAccessibilityAnnouncer()
        let model = RepositorySettingsConfigModel(
            repoPath: "/tmp/repo",
            updater: updater,
            errorMapper: RecordingCoreErrorMapper.repositorySettings(),
            accessibilityAnnouncer: announcer
        )
        var draft = RepositorySettingsConfigDraft(config: current)
        draft.overviewOutput = .rootAreaMatrixFile
        draft.contentLanguage = .en
        draft.iCloudWarn = false
        draft.fallbackToInbox = false

        let didSave = await model.save(draft: draft, currentConfig: current)

        XCTAssertTrue(didSave)
        await updater.assertConfigurationUpdateRequests([RecordingConfigurationUpdater.Request(
            repoPath: "/tmp/repo",
            config: current
                .withRepositorySettingsRepositorySettingsCoreOverviewOutput("RootAreaMatrixFile")
                .withRepositorySettingsRepositorySettingsCoreLocale("en")
                .withRepositorySettingsRepositorySettingsCoreICloudWarn(false)
                .withRepositorySettingsRepositorySettingsCoreFallbackToInbox(false)
        )])
        XCTAssertEqual(model.saveState, .saved("Repository settings saved."))
        announcer.assertAnnouncements(["Repository settings saved."])
    }

    @MainActor
    func testRepositorySettingsCrossPlatformRepositorySettingsCoreSaveFailureMapsCoreErrorAndKeepsPayloadObservable(
    ) async {
        let current = RepoConfigSnapshot.repositorySettingsConfigFixture(repoPath: "/tmp/repo")
        let updater =
            RecordingConfigurationUpdater(result: .failure(CoreError.PermissionDenied(path: "/tmp/repo")))
        let mapper = RecordingCoreErrorMapper.repositorySettings()
        let announcer = RecordingAccessibilityAnnouncer()
        let model = RepositorySettingsConfigModel(
            repoPath: "/tmp/repo",
            updater: updater,
            errorMapper: mapper,
            accessibilityAnnouncer: announcer
        )
        var draft = RepositorySettingsConfigDraft(config: current)
        draft.contentLanguage = .en

        let didSave = await model.save(draft: draft, currentConfig: current)

        XCTAssertFalse(didSave)
        await updater.assertRequestedConfigValues(\.locale, ["en"])
        await mapper.assertMappedCoreErrors([CoreError.PermissionDenied(path: "/tmp/repo")])
        XCTAssertEqual(model.saveState, .failed(RepositorySettingsConfigError(
            message: "权限错误",
            recovery: "Retry status"
        )))
        announcer.assertAnnouncements(["Repository settings could not be saved."])
    }
}

private extension RepoConfigSnapshot {
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
