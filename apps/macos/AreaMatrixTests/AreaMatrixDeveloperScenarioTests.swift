@testable import AreaMatrix
import XCTest

final class AreaMatrixDeveloperScenarioTests: XCTestCase {
    func testCatalogScenarioResolvesFromEnvironment() {
        XCTAssertEqual(
            AreaMatrixDeveloperScenario.resolve(environment: ["AREAMATRIX_SCENARIO": "ui-catalog"]),
            .uiCatalog
        )
        XCTAssertEqual(AreaMatrixDeveloperScenario.uiCatalog.colorScheme, .light)
        XCTAssertEqual(AreaMatrixDeveloperScenario.uiCatalogDark.colorScheme, .dark)
    }

    func testDeveloperScenariosCoverCatalogAndFeatureSurfacesInBothThemes() {
        XCTAssertEqual(AreaMatrixDeveloperScenario.allCases.map(\.rawValue), [
            "ui-catalog",
            "ui-catalog-dark",
            "onboarding",
            "onboarding-dark",
            "settings-language",
            "settings-language-dark"
        ])
        XCTAssertEqual(
            AreaMatrixDeveloperScenario.allCases.filter { $0.colorScheme == .light }.count,
            3
        )
        XCTAssertEqual(
            AreaMatrixDeveloperScenario.allCases.filter { $0.colorScheme == .dark }.count,
            3
        )
    }

    func testUnknownScenarioFailsClosedToNormalApplication() {
        XCTAssertNil(
            AreaMatrixDeveloperScenario.resolve(environment: ["AREAMATRIX_SCENARIO": "unknown"])
        )
    }

    @MainActor
    func testLanguageFixturesCoverFourUniqueResolvedCombinations() throws {
        let fixtures = AreaMatrixPreviewFixtures.languageCombinations

        XCTAssertEqual(fixtures.count, 4)
        XCTAssertEqual(fixtures.map(\.id), [
            "en-en",
            "en-zh-Hans",
            "zh-Hans-en",
            "zh-Hans-zh-Hans"
        ])
        XCTAssertEqual(Set(fixtures.map { "\($0.interfaceIdentifier)|\($0.contentIdentifier)" }).count, 4)
        XCTAssertEqual(fixtures.map(\.interfaceIdentifier), ["en", "en", "zh-Hans", "zh-Hans"])
        XCTAssertEqual(fixtures.map(\.contentIdentifier), ["en", "zh-Hans", "en", "zh-Hans"])

        for fixture in fixtures {
            let runtime = AppLanguageRuntime(selection: fixture.interfaceLanguage)
            let localizer = AppLocalizer(runtime: runtime)
            XCTAssertEqual(runtime.resolvedIdentifier(preferredLanguages: ["fr-FR"]), fixture.interfaceIdentifier)
            XCTAssertEqual(localizer.resourceLocaleIdentifier, fixture.interfaceIdentifier)
            XCTAssertEqual(
                try fixture.contentLanguage.resolvedIdentifier(
                    interfaceLocaleIdentifier: fixture.interfaceIdentifier
                ),
                fixture.contentIdentifier
            )
        }
    }

    @MainActor
    func testLanguageFixturesResolveBothCatalogResources() {
        let english = AppLocalizer(runtime: AppLanguageRuntime(selection: .en))
        let simplifiedChinese = AppLocalizer(runtime: AppLanguageRuntime(selection: .zhHans))

        XCTAssertEqual(english.string("settings.language.interface.title"), "Interface language")
        XCTAssertEqual(english.string("settings.language.content.title"), "Repository content language")
        XCTAssertEqual(simplifiedChinese.string("settings.language.interface.title"), "界面语言")
        XCTAssertEqual(simplifiedChinese.string("settings.language.content.title"), "资料库内容语言")
    }

    @MainActor
    func testCatalogBodyCanBeConstructedWithLanguageMatrix() {
        _ = AreaMatrixUICatalog().body
    }

    @MainActor
    func testEveryDeveloperScenarioBodyCanBeConstructedWithoutRepositoryIO() {
        for scenario in AreaMatrixDeveloperScenario.allCases {
            _ = AreaMatrixDeveloperScenarioView(scenario: scenario).body
        }
    }
}
