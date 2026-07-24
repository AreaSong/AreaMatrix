import AppKit
@testable import AreaMatrix
import Observation
import XCTest

final class AppLanguageTests: XCTestCase {
    func testSystemLanguageResolutionSupportsEnglishAndSimplifiedChinese() {
        XCTAssertEqual(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["en-US"]), "en")
        XCTAssertEqual(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["zh-Hans-CN"]), "zh-Hans")
        XCTAssertEqual(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["zh-CN"]), "zh-Hans")
        XCTAssertEqual(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["zh-SG"]), "zh-Hans")
    }

    func testTraditionalChineseSystemLanguageFallsBackToEnglish() {
        XCTAssertEqual(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["zh-Hant-TW"]), "en")
        XCTAssertEqual(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["zh-HK"]), "en")
    }

    func testBareChineseDoesNotImplySimplifiedChinese() {
        XCTAssertEqual(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["zh"]), "en")
    }

    func testSystemResolutionUsesOnlyFirstPreferredLanguage() {
        XCTAssertEqual(
            AppLanguage.system.resolvedIdentifier(preferredLanguages: ["ja-JP", "zh-Hant-TW", "en-GB"]),
            "en"
        )
        XCTAssertEqual(
            AppLanguage.system.resolvedIdentifier(preferredLanguages: ["zh-Hant-TW", "zh-SG", "en-US"]),
            "en"
        )
        XCTAssertEqual(
            AppLanguage.system.resolvedIdentifier(preferredLanguages: ["fr-FR", "zh-Hans"]),
            "en"
        )
    }

    func testSystemLanguageResolutionFallsBackToEnglish() {
        XCTAssertEqual(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["ja-JP"]), "en")
        XCTAssertEqual(AppLanguage.system.resolvedIdentifier(preferredLanguages: []), "en")
    }

    func testLanguageCycleUsesSystemChineseEnglishOrder() {
        XCTAssertEqual(AppLanguage.system.next, .zhHans)
        XCTAssertEqual(AppLanguage.zhHans.next, .en)
        XCTAssertEqual(AppLanguage.en.next, .system)
    }

    func testRepositoryContentLanguageCompatibilityAndUnsupportedValues() throws {
        XCTAssertEqual(RepositoryContentLanguage(snapshotValue: ""), .followInterface)
        XCTAssertEqual(RepositoryContentLanguage(snapshotValue: "system"), .followInterface)
        XCTAssertEqual(RepositoryContentLanguage(snapshotValue: "zh-CN"), .zhHans)
        XCTAssertEqual(RepositoryContentLanguage(snapshotValue: "zh-SG"), .zhHans)
        XCTAssertEqual(RepositoryContentLanguage(snapshotValue: "en-US"), .en)
        XCTAssertEqual(RepositoryContentLanguage(snapshotValue: "zh-Hant"), .unsupported("zh-Hant"))
        XCTAssertThrowsError(
            try RepositoryContentLanguage.unsupported("fr-FR").resolvedIdentifier(
                interfaceLocaleIdentifier: "en"
            )
        )
    }

    func testRepositoryFollowInterfaceUsesResolvedInterfaceLocaleOnly() throws {
        XCTAssertEqual(
            try RepositoryContentLanguage.followInterface.resolvedIdentifier(interfaceLocaleIdentifier: "zh-Hans"),
            "zh-Hans"
        )
        XCTAssertEqual(
            try RepositoryContentLanguage.followInterface.resolvedIdentifier(interfaceLocaleIdentifier: "en"),
            "en"
        )
    }

    @MainActor
    func testLegacyChinesePreferenceIsReadAndWrittenBackCanonically() throws {
        let defaults = try makeDefaults()
        defaults.set("zh-CN", forKey: AppLanguage.defaultsKey)

        let store = AppLanguageStore(defaults: defaults, runtime: AppLanguageRuntime())

        XCTAssertEqual(store.selection, .zhHans)
        XCTAssertEqual(defaults.string(forKey: AppLanguage.defaultsKey), "zh-Hans")
    }

    @MainActor
    func testUnknownPreferenceRunsAsSystemWithoutImplicitWriteBack() throws {
        let defaults = try makeDefaults()
        defaults.set("fr-FR", forKey: AppLanguage.defaultsKey)
        let runtime = AppLanguageRuntime()

        let store = AppLanguageStore(
            defaults: defaults,
            runtime: runtime,
            preferredLanguages: { ["zh-CN"] }
        )

        XCTAssertEqual(store.selection, .system)
        XCTAssertEqual(store.resolvedResourceLocaleIdentifier, "zh-Hans")
        XCTAssertEqual(defaults.string(forKey: AppLanguage.defaultsKey), "fr-FR")
    }

    @MainActor
    func testSelectionPersistsAndUpdatesRuntimeImmediately() throws {
        let defaults = try makeDefaults()
        let runtime = AppLanguageRuntime()
        let store = AppLanguageStore(
            defaults: defaults,
            runtime: runtime
        )

        store.select(.zhHans)

        XCTAssertEqual(defaults.string(forKey: AppLanguage.defaultsKey), "zh-Hans")
        XCTAssertEqual(runtime.resolvedIdentifier(preferredLanguages: ["en-US"]), "zh-Hans")
    }

    @MainActor
    func testSelectNextPersistsEveryLanguageModeWithoutCoreLocaleState() throws {
        let defaults = try makeDefaults()
        let runtime = AppLanguageRuntime()
        let store = AppLanguageStore(
            defaults: defaults,
            runtime: runtime
        )

        store.selectNext()
        XCTAssertEqual(store.selection, .zhHans)
        store.selectNext()
        XCTAssertEqual(store.selection, .en)
        store.selectNext()
        XCTAssertEqual(store.selection, .system)

        XCTAssertEqual(defaults.string(forKey: AppLanguage.defaultsKey), "system")
        XCTAssertEqual(runtime.resolvedIdentifier(preferredLanguages: ["en-US"]), "en")
    }

    func testRuntimeLoadsBothCatalogLocalizationsFromApplicationBundle() {
        let runtime = AppLanguageRuntime(selection: .en)
        XCTAssertEqual(runtime.localizedString("settings.page.general"), "General")

        runtime.update(.zhHans)
        XCTAssertEqual(runtime.localizedString("settings.page.general"), "通用")
    }

    func testRuntimeLocalizationRegistersAnObservationDependency() {
        let runtime = AppLanguageRuntime(selection: .en)
        let invalidated = expectation(description: "localized dependency invalidated")

        withObservationTracking {
            _ = runtime.localizedString("settings.page.general")
        } onChange: {
            invalidated.fulfill()
        }

        runtime.update(.zhHans)

        wait(for: [invalidated], timeout: 0.1)
        XCTAssertEqual(runtime.localizedString("settings.page.general"), "通用")
    }

    @MainActor
    func testPluralCatalogUsesCurrentInterfaceLanguage() {
        let runtime = AppLanguageRuntime(selection: .en)
        let localizer = AppLocalizer(runtime: runtime)
        XCTAssertEqual(localizer.plural("common.fileCount", count: 1), "1 file")
        XCTAssertEqual(localizer.plural("common.fileCount", count: 2), "2 files")

        localizer.apply(.zhHans)
        XCTAssertEqual(localizer.plural("common.fileCount", count: 2), "2 个文件")
    }

    @MainActor
    func testResourceLanguageSwitchKeepsInjectedRegionalFormattingLocale() {
        let runtime = AppLanguageRuntime(selection: .en)
        let regionalLocale = Locale(identifier: "fr_FR")
        let localizer = AppLocalizer(runtime: runtime, formattingLocale: { regionalLocale })

        XCTAssertEqual(localizer.resourceLocaleIdentifier, "en")
        XCTAssertEqual(localizer.regionalFormattingLocale.identifier, "fr_FR")

        localizer.apply(.zhHans)

        XCTAssertEqual(localizer.resourceLocaleIdentifier, "zh-Hans")
        XCTAssertEqual(localizer.regionalFormattingLocale.identifier, "fr_FR")
    }

    @MainActor
    func testLocalizerPublishesResolvedLocaleAfterRuntimeHasUpdated() {
        let runtime = AppLanguageRuntime(selection: .en)
        let localizer = AppLocalizer(runtime: runtime)
        var publishedIdentifiers: [String] = []
        let observation = localizer.$resourceLocaleIdentifier.dropFirst().sink { identifier in
            publishedIdentifiers.append(identifier)
        }

        localizer.apply(.zhHans, preferredLanguages: ["en-US"])

        XCTAssertEqual(localizer.resourceLocaleIdentifier, "zh-Hans")
        XCTAssertEqual(runtime.resolvedIdentifier(preferredLanguages: ["en-US"]), "zh-Hans")
        XCTAssertEqual(publishedIdentifiers, ["zh-Hans"])
        withExtendedLifetime(observation) {}
    }

    @MainActor
    func testLocalizerResolvesMessagesAndVerbatimValues() {
        let runtime = AppLanguageRuntime(selection: .en)
        let localizer = AppLocalizer(runtime: runtime)

        XCTAssertEqual(
            localizer.resolve(L10n.message(
                "mainList.diagnosticsCollected",
                arguments: [.string("/tmp/diagnostics.json")]
            )),
            "Diagnostics collected: /tmp/diagnostics.json"
        )
        XCTAssertEqual(
            localizer.resolve(.verbatim("gpt-4.1-mini", reason: .technicalIdentifier)),
            "gpt-4.1-mini"
        )
    }

    @MainActor
    func testStorePublishesOnlyAfterLocalizerUsesNewLanguage() throws {
        let defaults = try makeDefaults()
        let runtime = AppLanguageRuntime(selection: .en)
        let localizer = AppLocalizer(runtime: runtime)
        let store = AppLanguageStore(
            defaults: defaults,
            runtime: runtime,
            localizer: localizer
        )
        var localeAtSelectionPublication: String?
        let observation = store.$selection.dropFirst().sink { _ in
            localeAtSelectionPublication = localizer.resourceLocaleIdentifier
        }

        store.select(.zhHans)

        XCTAssertEqual(localeAtSelectionPublication, "zh-Hans")
        withExtendedLifetime(observation) {}
    }

    @MainActor
    func testSystemLocaleNotificationRefreshesOnlyFollowSystemSelection() throws {
        let defaults = try makeDefaults()
        let notifications = NotificationCenter()
        var preferred = ["en-US"]
        let runtime = AppLanguageRuntime(selection: .system)
        let localizer = AppLocalizer(runtime: runtime)
        let store = AppLanguageStore(
            defaults: defaults,
            runtime: runtime,
            localizer: localizer,
            preferredLanguages: { preferred },
            notificationCenter: notifications
        )
        XCTAssertEqual(localizer.resourceLocaleIdentifier, "en")

        preferred = ["zh-CN"]
        notifications.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        XCTAssertEqual(localizer.resourceLocaleIdentifier, "zh-Hans")

        store.select(.en)
        preferred = ["zh-CN"]
        notifications.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        XCTAssertEqual(localizer.resourceLocaleIdentifier, "en")
    }

    @MainActor
    func testApplicationActivationReResolvesFollowSystemSelection() throws {
        let defaults = try makeDefaults()
        let notifications = NotificationCenter()
        var preferred = ["en-US"]
        let runtime = AppLanguageRuntime(selection: .system)
        let localizer = AppLocalizer(runtime: runtime)
        let store = AppLanguageStore(
            defaults: defaults,
            runtime: runtime,
            localizer: localizer,
            preferredLanguages: { preferred },
            notificationCenter: notifications
        )
        XCTAssertEqual(localizer.resourceLocaleIdentifier, "en")

        preferred = ["zh-SG"]
        notifications.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))

        XCTAssertEqual(localizer.resourceLocaleIdentifier, "zh-Hans")
        withExtendedLifetime(store) {}
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "AppLanguageTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}
