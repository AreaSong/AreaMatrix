@testable import AreaMatrix
import XCTest

final class AppLanguageTests: XCTestCase {
    func testSystemLanguageResolutionSupportsEnglishAndAllChineseVariants() {
        XCTAssertEqual(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["en-US"]), "en")
        XCTAssertEqual(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["zh-Hans-CN"]), "zh-Hans")
        XCTAssertEqual(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["zh-Hant-TW"]), "zh-Hans")
    }

    func testSystemLanguageResolutionFallsBackToEnglish() {
        XCTAssertEqual(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["ja-JP"]), "en")
        XCTAssertEqual(AppLanguage.system.resolvedIdentifier(preferredLanguages: []), "en")
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
    func testSelectionPersistsAndUpdatesRuntimeImmediately() throws {
        let defaults = try makeDefaults()
        let runtime = AppLanguageRuntime()
        let initialLocale = AppLanguage.system.resolvedIdentifier(preferredLanguages: Locale.preferredLanguages)
        var syncedLocales: [String] = []
        let store = AppLanguageStore(
            defaults: defaults,
            runtime: runtime,
            coreLocaleUpdater: { syncedLocales.append($0) }
        )

        store.select(.zhHans)

        XCTAssertEqual(defaults.string(forKey: AppLanguage.defaultsKey), "zh-Hans")
        XCTAssertEqual(runtime.resolvedIdentifier(preferredLanguages: ["en-US"]), "zh-Hans")
        XCTAssertEqual(syncedLocales, [initialLocale, "zh-Hans"])
        XCTAssertNil(store.coreSyncError)
    }

    @MainActor
    func testCoreLocaleSyncFailureDoesNotDiscardInterfaceSelection() throws {
        struct SyncFailure: Error {}

        let defaults = try makeDefaults()
        let runtime = AppLanguageRuntime()
        let store = AppLanguageStore(
            defaults: defaults,
            runtime: runtime,
            coreLocaleUpdater: { _ in throw SyncFailure() }
        )

        store.select(.en)

        XCTAssertEqual(store.selection, .en)
        XCTAssertEqual(defaults.string(forKey: AppLanguage.defaultsKey), "en")
        XCTAssertNotNil(store.coreSyncError)
    }

    func testRuntimeLoadsBothCatalogLocalizationsFromApplicationBundle() {
        let runtime = AppLanguageRuntime(selection: .en)
        XCTAssertEqual(runtime.localizedString("settings.page.general"), "General")

        runtime.update(.zhHans)
        XCTAssertEqual(runtime.localizedString("settings.page.general"), "通用")
    }

    func testPluralCatalogUsesCurrentInterfaceLanguage() {
        defer { AppLanguageRuntime.shared.update(.system) }
        AppLanguageRuntime.shared.update(.en)
        XCTAssertEqual(L10n.plural("common.fileCount", count: 1), "1 file")
        XCTAssertEqual(L10n.plural("common.fileCount", count: 2), "2 files")

        AppLanguageRuntime.shared.update(.zhHans)
        XCTAssertEqual(L10n.plural("common.fileCount", count: 2), "2 个文件")
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
