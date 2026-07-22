import Combine
import Foundation

enum AppLanguage: String, CaseIterable, Equatable, Identifiable {
    case system
    case zhHans = "zh-Hans"
    case en

    static let defaultsKey = "AreaMatrix.interfaceLanguage"

    var id: String {
        rawValue
    }

    var labelKey: String {
        switch self {
        case .system:
            "settings.language.system"
        case .zhHans:
            "settings.language.simplifiedChinese"
        case .en:
            "settings.language.english"
        }
    }

    init(persistedValue: String?) {
        switch persistedValue?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "zh-CN", "zh-Hans":
            self = .zhHans
        case "en":
            self = .en
        default:
            self = .system
        }
    }

    func resolvedIdentifier(preferredLanguages: [String]) -> String {
        switch self {
        case .system:
            for language in preferredLanguages {
                if let supported = Self.supportedIdentifier(for: language) {
                    return supported
                }
            }
            return "en"
        case .zhHans:
            return "zh-Hans"
        case .en:
            return "en"
        }
    }

    private static func supportedIdentifier(for language: String) -> String? {
        let normalized = language
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()

        if normalized == "zh" || normalized.hasPrefix("zh-") {
            return "zh-Hans"
        }
        if normalized == "en" || normalized.hasPrefix("en-") {
            return "en"
        }
        return nil
    }
}

final class AppLanguageRuntime: @unchecked Sendable {
    static let shared = AppLanguageRuntime()

    private let lock = NSLock()
    private var selection: AppLanguage

    init(selection: AppLanguage = .system) {
        self.selection = selection
    }

    func update(_ selection: AppLanguage) {
        lock.withLock {
            self.selection = selection
        }
    }

    func resolvedIdentifier(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        lock.withLock {
            selection.resolvedIdentifier(preferredLanguages: preferredLanguages)
        }
    }

    func preferredContentLanguages(preferredLanguages: [String] = Locale.preferredLanguages) -> [String] {
        [resolvedIdentifier(preferredLanguages: preferredLanguages)]
    }

    func localizedString(
        _ key: String,
        fallback: String? = nil,
        table: String? = nil,
        bundle: Bundle = .main,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        let identifier = resolvedIdentifier(preferredLanguages: preferredLanguages)
        guard let path = bundle.path(forResource: identifier, ofType: "lproj"),
              let localizedBundle = Bundle(path: path)
        else {
            return bundle.localizedString(forKey: key, value: fallback ?? key, table: table)
        }
        return localizedBundle.localizedString(forKey: key, value: fallback ?? key, table: table)
    }
}

@MainActor
final class AppLanguageStore: ObservableObject {
    @Published private(set) var selection: AppLanguage
    @Published private(set) var coreSyncError: Error?

    private let defaults: UserDefaults
    private let defaultsKey: String
    private let runtime: AppLanguageRuntime
    private let coreLocaleUpdater: (String) throws -> Void

    init(
        defaults: UserDefaults = .standard,
        defaultsKey: String = AppLanguage.defaultsKey,
        runtime: AppLanguageRuntime = .shared,
        coreLocaleUpdater: @escaping (String) throws -> Void = CoreBridge.updateAppInterfaceLocale
    ) {
        self.defaults = defaults
        self.defaultsKey = defaultsKey
        self.runtime = runtime
        self.coreLocaleUpdater = coreLocaleUpdater
        let initialSelection = AppLanguage(persistedValue: defaults.string(forKey: defaultsKey))
        selection = initialSelection
        if defaults.string(forKey: defaultsKey) != initialSelection.rawValue {
            defaults.set(initialSelection.rawValue, forKey: defaultsKey)
        }
        runtime.update(initialSelection)
        syncCoreLocale()
    }

    var resolvedLocale: Locale {
        Locale(identifier: runtime.resolvedIdentifier())
    }

    func select(_ language: AppLanguage) {
        guard language != selection else { return }
        selection = language
        defaults.set(language.rawValue, forKey: defaultsKey)
        runtime.update(language)
        syncCoreLocale()
    }

    func localizedString(_ key: String) -> String {
        runtime.localizedString(key)
    }

    private func syncCoreLocale() {
        do {
            try coreLocaleUpdater(runtime.resolvedIdentifier())
            coreSyncError = nil
        } catch {
            coreSyncError = error
        }
    }
}

enum L10n {
    static func string(_ key: String, fallback: String? = nil) -> String {
        AppLanguageRuntime.shared.localizedString(key, fallback: fallback)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        let locale = Locale(identifier: AppLanguageRuntime.shared.resolvedIdentifier())
        return String(format: string(key), locale: locale, arguments: arguments)
    }

    static func plural(_ key: String, count: Int) -> String {
        String.localizedStringWithFormat(string(key), count)
    }

    static func plural(_ key: String, count: Int64) -> String {
        String.localizedStringWithFormat(string(key), count)
    }
}
