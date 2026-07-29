import SwiftUI

#if DEBUG
enum AreaMatrixDeveloperScenario: String, CaseIterable {
    case uiCatalog = "ui-catalog"
    case uiCatalogDark = "ui-catalog-dark"
    case onboarding
    case onboardingDark = "onboarding-dark"
    case settingsLanguage = "settings-language"
    case settingsLanguageDark = "settings-language-dark"

    var colorScheme: ColorScheme {
        switch self {
        case .uiCatalog, .onboarding, .settingsLanguage:
            .light
        case .uiCatalogDark, .onboardingDark, .settingsLanguageDark:
            .dark
        }
    }

    static var current: Self? {
        resolve(environment: ProcessInfo.processInfo.environment)
    }

    static func resolve(environment: [String: String]) -> Self? {
        guard let value = environment["AREAMATRIX_SCENARIO"] else { return nil }
        return Self(rawValue: value)
    }
}

struct AreaMatrixDeveloperScenarioView: View {
    let scenario: AreaMatrixDeveloperScenario

    var body: some View {
        Group {
            switch scenario {
            case .uiCatalog, .uiCatalogDark:
                AreaMatrixPreviewSurface {
                    AreaMatrixUICatalog()
                }
            case .onboarding, .onboardingDark:
                WelcomeStepView(onContinue: {}, onLearnMore: {})
                    .frame(width: 900, height: 680)
            case .settingsLanguage, .settingsLanguageDark:
                AreaMatrixLanguageDeveloperScenarioView()
                    .frame(width: 900, height: 680)
            }
        }
        .preferredColorScheme(scenario.colorScheme)
    }
}

private struct AreaMatrixLanguageDeveloperScenarioView: View {
    private let configStore: DeveloperConfigurationStore
    private let capabilityLoader = DeveloperCapabilityLoader()
    private let overviewRegenerator = DeveloperOverviewRegenerator()

    init() {
        configStore = DeveloperConfigurationStore(config: AppRepoConfigSnapshot(
            repoPath: AreaMatrixPreviewFixtures.repositoryPath,
            revision: 7,
            defaultMode: "Copied",
            overviewOutput: "AreaMatrix",
            aiEnabled: false,
            locale: "en",
            iCloudWarn: true,
            enableExtensionRules: true,
            enableKeywordRules: true,
            fallbackToInbox: true,
            allowReplaceDuringImport: false
        ))
    }

    var body: some View {
        LanguageSettingsPane(
            repoPath: AreaMatrixPreviewFixtures.repositoryPath,
            loader: configStore,
            updater: configStore,
            capabilityLoader: capabilityLoader,
            overviewRegenerator: overviewRegenerator,
            appVersion: "Developer Scenario"
        )
        .background(.background)
        .accessibilityIdentifier("developer.languageSettings")
    }
}

#endif
