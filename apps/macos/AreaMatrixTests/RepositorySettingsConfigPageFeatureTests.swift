@testable import AreaMatrix
import XCTest

final class RepositorySettingsConfigPageFeatureTests: XCTestCase {
    @MainActor
    func testLanguageSettingsLoadsCurrentRepositoryLanguageWithoutWritingConfig() async {
        let config = AppRepoConfigSnapshot.testFixture(repoPath: "/tmp/repo") {
            $0.revision = 7
            $0.locale = "zh-Hans"
        }
        let loader = RecordingConfigurationLoader(result: .success(config))
        let updater = RecordingConfigurationUpdater(result: .success(()))
        let model = RepositorySettingsConfigModel(
            repoPath: "/tmp/repo",
            loader: loader,
            updater: updater,
            errorMapper: RecordingCoreErrorMapper.repositorySettings(),
            accessibilityAnnouncer: NoopAccessibilityAnnouncer()
        )

        await model.load()

        await loader.assertRequestedPaths(["/tmp/repo"])
        await updater.assertNoConfigurationUpdateRequests()
        XCTAssertEqual(model.loadedConfig, config)
        XCTAssertNil(model.loadError)
    }

    @MainActor
    func testLanguageSettingsSaveChangesOnlyContentLanguage() async {
        let current = AppRepoConfigSnapshot.testFixture(repoPath: "/tmp/repo") {
            $0.revision = 4
            $0.overviewOutput = "RootAreaMatrixFile"
            $0.locale = "system"
            $0.iCloudWarn = false
            $0.fallbackToInbox = false
        }
        let updater = RecordingConfigurationUpdater(result: .success(()))
        let model = RepositorySettingsConfigModel(
            repoPath: "/tmp/repo",
            loader: StaticConfigurationLoader(config: current),
            updater: updater,
            errorMapper: RecordingCoreErrorMapper.repositorySettings(),
            accessibilityAnnouncer: NoopAccessibilityAnnouncer()
        )

        let didSave = await model.saveContentLanguage(RepositoryContentLanguage.en, currentConfig: current)

        XCTAssertTrue(didSave)
        await updater.assertConfigurationUpdateRequests([RecordingConfigurationUpdater.Request(
            repoPath: "/tmp/repo",
            config: current.withRepositorySettingsRepositorySettingsCoreLocale("en")
        )])
        XCTAssertEqual(model.loadedConfig?.revision, 5)
        XCTAssertEqual(model.loadedConfig?.overviewOutput, "RootAreaMatrixFile")
        XCTAssertEqual(model.loadedConfig?.iCloudWarn, false)
        XCTAssertEqual(model.loadedConfig?.fallbackToInbox, false)
    }

    @MainActor
    func testRepositorySettingsCrossPlatformRepositorySettingsCoreSavesRepositoryConfigThroughUpdateConfig() async {
        let current = AppRepoConfigSnapshot.repositorySettingsConfigFixture(repoPath: "/tmp/repo")
        let updater = RecordingConfigurationUpdater(result: .success(()))
        let announcer = RecordingAccessibilityAnnouncer()
        let model = RepositorySettingsConfigModel(
            repoPath: "/tmp/repo",
            loader: StaticConfigurationLoader(config: current),
            updater: updater,
            errorMapper: RecordingCoreErrorMapper.repositorySettings(),
            accessibilityAnnouncer: announcer
        )
        var draft = RepositorySettingsConfigDraft(config: current)
        draft.overviewOutput = .rootAreaMatrixFile
        draft.contentLanguage = .en
        draft.iCloudWarn = false
        draft.fallbackToInbox = false

        let didSave = await model.save(
            draft: draft,
            currentConfig: current,
            dirtyFields: draft.dirtyFields(comparedTo: current)
        )

        XCTAssertTrue(didSave)
        await updater.assertConfigurationUpdateRequests([RecordingConfigurationUpdater.Request(
            repoPath: "/tmp/repo",
            config: current
                .withRepositorySettingsRepositorySettingsCoreOverviewOutput("RootAreaMatrixFile")
                .withRepositorySettingsRepositorySettingsCoreLocale("en")
                .withRepositorySettingsRepositorySettingsCoreICloudWarn(false)
                .withRepositorySettingsRepositorySettingsCoreFallbackToInbox(false)
        )])
        XCTAssertEqual(model.saveState, .saved(L10n.message("Repository settings saved.")))
        announcer.assertAnnouncementDescriptors([L10n.message("Repository settings saved.")])
    }

    @MainActor
    func testRepositorySettingsCrossPlatformRepositorySettingsCoreSaveFailureMapsCoreErrorAndKeepsPayloadObservable(
    ) async {
        let current = AppRepoConfigSnapshot.repositorySettingsConfigFixture(repoPath: "/tmp/repo")
        let updater =
            RecordingConfigurationUpdater(result: .failure(CoreError.PermissionDenied(path: "/tmp/repo")))
        let mapper = RecordingCoreErrorMapper.repositorySettings()
        let announcer = RecordingAccessibilityAnnouncer()
        let model = RepositorySettingsConfigModel(
            repoPath: "/tmp/repo",
            loader: StaticConfigurationLoader(config: current),
            updater: updater,
            errorMapper: mapper,
            accessibilityAnnouncer: announcer
        )
        var draft = RepositorySettingsConfigDraft(config: current)
        draft.contentLanguage = .en

        let didSave = await model.save(
            draft: draft,
            currentConfig: current,
            dirtyFields: draft.dirtyFields(comparedTo: current)
        )

        XCTAssertFalse(didSave)
        await updater.assertRequestedConfigValues(\.locale, ["en"])
        await mapper.assertMappedCoreErrors([CoreError.PermissionDenied(path: "/tmp/repo")])
        XCTAssertEqual(model.saveState, .failed(RepositorySettingsConfigError(
            message: L10n.message("error.unmapped.message", fallback: "权限错误", technicalDetail: "权限错误"),
            recovery: L10n.message(
                "error.unmapped.action",
                fallback: "Retry status",
                technicalDetail: "Retry status"
            )
        )))
        announcer.assertAnnouncementDescriptors([L10n.message("Repository settings could not be saved.")])
    }

    @MainActor
    func testRevisionConflictRequiresExplicitReviewAndSecondSave() async {
        let fixture = makeRepositoryRevisionConflictFixture()
        let current = fixture.current
        let updater = fixture.updater
        let model = fixture.model
        var local = RepositorySettingsConfigDraft(config: current)
        local.contentLanguage = .en
        let dirtyFields = local.dirtyFields(comparedTo: current)

        let firstSave = await model.save(
            draft: local,
            currentConfig: current,
            dirtyFields: dirtyFields
        )

        XCTAssertFalse(firstSave)
        guard case let .conflict(conflict) = model.saveState else {
            return XCTFail("stale save must enter explicit conflict review")
        }
        XCTAssertEqual(conflict.saved.revision, 2)
        XCTAssertEqual(conflict.latest.revision, 3)
        XCTAssertEqual(conflict.local.contentLanguage, .en)
        XCTAssertEqual(conflict.dirtyFields, [.contentLanguage])

        let reviewedDraft = conflict.local.rebased(
            onto: conflict.latest,
            preserving: conflict.dirtyFields
        )
        XCTAssertEqual(reviewedDraft.overviewOutput, .rootAreaMatrixFile)
        XCTAssertEqual(reviewedDraft.contentLanguage, .en)

        model.resetFeedback()
        let secondSave = await model.save(
            draft: reviewedDraft,
            currentConfig: conflict.latest,
            dirtyFields: conflict.dirtyFields
        )

        XCTAssertTrue(secondSave)
        await updater.assertRequestCount(2)
        await updater.assertRequestedConfigValues(\.overviewOutput, ["GeneratedOnly", "RootAreaMatrixFile"])
        await updater.assertRequestedConfigValues(\.locale, ["en", "en"])
        XCTAssertEqual(model.lastSavedConfig?.revision, 4)
    }
}

@MainActor
private func makeRepositoryRevisionConflictFixture() -> RepositoryRevisionConflictFixture {
    let current = AppRepoConfigSnapshot.testFixture(repoPath: "/tmp/repo") {
        $0.revision = 2
        $0.overviewOutput = "GeneratedOnly"
        $0.locale = "system"
    }
    let latest = AppRepoConfigSnapshot.testFixture(repoPath: "/tmp/repo") {
        $0.revision = 3
        $0.overviewOutput = "RootAreaMatrixFile"
        $0.locale = "system"
    }
    let updater = RecordingConfigurationUpdater(results: [
        .failure(CoreError.RevisionConflict(resource: "repo_config", expectedRevision: 2, currentRevision: 3)),
        .success(())
    ])
    let model = RepositorySettingsConfigModel(
        repoPath: "/tmp/repo",
        loader: StaticConfigurationLoader(config: latest),
        updater: updater,
        errorMapper: RecordingCoreErrorMapper.repositorySettings(),
        accessibilityAnnouncer: NoopAccessibilityAnnouncer()
    )
    return RepositoryRevisionConflictFixture(current: current, updater: updater, model: model)
}

private struct RepositoryRevisionConflictFixture {
    var current: AppRepoConfigSnapshot
    var updater: RecordingConfigurationUpdater
    var model: RepositorySettingsConfigModel
}

private extension AppRepoConfigSnapshot {
    func withRepositorySettingsRepositorySettingsCoreOverviewOutput(_ value: String) -> AppRepoConfigSnapshot {
        var config = self
        config.overviewOutput = value
        return config
    }

    func withRepositorySettingsRepositorySettingsCoreLocale(_ value: String) -> AppRepoConfigSnapshot {
        var config = self
        config.locale = value
        return config
    }

    func withRepositorySettingsRepositorySettingsCoreICloudWarn(_ value: Bool) -> AppRepoConfigSnapshot {
        var config = self
        config.iCloudWarn = value
        return config
    }

    func withRepositorySettingsRepositorySettingsCoreFallbackToInbox(_ value: Bool) -> AppRepoConfigSnapshot {
        var config = self
        config.fallbackToInbox = value
        return config
    }
}
