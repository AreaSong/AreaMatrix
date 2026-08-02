import SwiftUI

#if DEBUG
enum AreaMatrixPreviewTheme: String, CaseIterable, Hashable, Identifiable {
    case light
    case dark

    var id: String {
        rawValue
    }

    var colorScheme: ColorScheme {
        switch self {
        case .light: .light
        case .dark: .dark
        }
    }
}

enum AreaMatrixPreviewLanguage: String, CaseIterable, Hashable, Identifiable {
    case en
    case zhHans = "zh-Hans"

    var id: String {
        rawValue
    }

    var appLanguage: AppLanguage {
        switch self {
        case .en: .en
        case .zhHans: .zhHans
        }
    }
}

enum AreaMatrixPreviewViewport: String, CaseIterable, Hashable, Identifiable {
    case compact
    case standard
    case wide

    var id: String {
        rawValue
    }

    var size: CGSize {
        switch self {
        case .compact: CGSize(width: 760, height: 520)
        case .standard: CGSize(width: 900, height: 680)
        case .wide: CGSize(width: 1200, height: 760)
        }
    }
}

enum AreaMatrixPreviewStateKind: String, CaseIterable, Hashable, Identifiable {
    case loading
    case empty
    case success
    case failed
    case disabled
    case blocked
    case stale
    case unavailable

    var id: String {
        rawValue
    }
}

struct AreaMatrixDeveloperScenarioConfiguration: Equatable {
    var scenario: AreaMatrixDeveloperScenario
    var theme: AreaMatrixPreviewTheme
    var language: AreaMatrixPreviewLanguage
    var viewport: AreaMatrixPreviewViewport

    static let launcher = AreaMatrixDeveloperScenarioConfiguration(
        scenario: .launcher,
        theme: .light,
        language: .en,
        viewport: .wide
    )

    static func resolve(environment: [String: String]) -> AreaMatrixDeveloperScenarioConfiguration? {
        guard let rawScenario = environment["AREAMATRIX_SCENARIO"] else { return nil }
        let legacy = legacyScenario(rawScenario)
        guard let scenario = legacy?.scenario ?? AreaMatrixDeveloperScenario(rawValue: rawScenario) else {
            return nil
        }

        return AreaMatrixDeveloperScenarioConfiguration(
            scenario: scenario,
            theme: environment["AREAMATRIX_SCENARIO_THEME"].flatMap(AreaMatrixPreviewTheme.init)
                ?? legacy?.theme
                ?? .light,
            language: environment["AREAMATRIX_SCENARIO_LOCALE"].flatMap(AreaMatrixPreviewLanguage.init)
                ?? .en,
            viewport: environment["AREAMATRIX_SCENARIO_VIEWPORT"].flatMap(AreaMatrixPreviewViewport.init)
                ?? (scenario == .launcher ? .wide : .standard)
        )
    }

    private static func legacyScenario(
        _ rawValue: String
    ) -> (scenario: AreaMatrixDeveloperScenario, theme: AreaMatrixPreviewTheme)? {
        switch rawValue {
        case "ui-catalog-dark": (.uiCatalog, .dark)
        case "onboarding-dark": (.onboarding, .dark)
        case "settings-language-dark": (.settingsLanguage, .dark)
        default: nil
        }
    }
}
#endif
