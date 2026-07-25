import AppKit
import Combine
import Foundation
import Observation

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

    var displayMessage: LocalizedMessage {
        switch self {
        case .system:
            L10n.message("settings.language.system")
        case .zhHans:
            L10n.message("settings.language.simplifiedChinese")
        case .en:
            L10n.message("settings.language.english")
        }
    }

    var next: AppLanguage {
        switch self {
        case .system:
            .zhHans
        case .zhHans:
            .en
        case .en:
            .system
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

    static func canonicalPersistedValue(for persistedValue: String?) -> String? {
        switch persistedValue?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "zh-CN", "zh-Hans":
            AppLanguage.zhHans.rawValue
        case "en":
            AppLanguage.en.rawValue
        case "system":
            AppLanguage.system.rawValue
        default:
            nil
        }
    }

    func resolvedIdentifier(preferredLanguages: [String]) -> String {
        switch self {
        case .system:
            guard let primaryLanguage = preferredLanguages.first else { return "en" }
            return Self.supportedIdentifier(for: primaryLanguage) ?? "en"
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

        if normalized.hasPrefix("zh-hans") ||
            normalized.hasPrefix("zh-cn") ||
            normalized.hasPrefix("zh-sg") {
            return "zh-Hans"
        }
        if normalized == "en" || normalized.hasPrefix("en-") {
            return "en"
        }
        return nil
    }
}

enum RepositoryContentLanguage: CaseIterable, Equatable, Hashable, Identifiable {
    case followInterface
    case zhHans
    case en
    case unsupported(String)

    static let allCases: [RepositoryContentLanguage] = [.followInterface, .zhHans, .en]

    var id: String {
        snapshotValue
    }

    init(snapshotValue: String) {
        let trimmed = snapshotValue.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed {
        case "", "system":
            self = .followInterface
        case "en":
            self = .en
        case "zh-CN", "zh-Hans", "zh-SG":
            self = .zhHans
        default:
            let normalized = trimmed.replacingOccurrences(of: "_", with: "-").lowercased()
            if normalized.hasPrefix("zh-hans-") {
                self = .zhHans
            } else if normalized.hasPrefix("en-") {
                self = .en
            } else {
                self = .unsupported(trimmed)
            }
        }
    }

    var snapshotValue: String {
        switch self {
        case .followInterface:
            "system"
        case .zhHans:
            "zh-Hans"
        case .en:
            "en"
        case let .unsupported(identifier):
            identifier
        }
    }

    var labelKey: String {
        switch self {
        case .followInterface:
            "settings.language.followInterface"
        case .zhHans:
            "settings.language.simplifiedChinese"
        case .en:
            "settings.language.english"
        case .unsupported:
            "settings.language.unsupported"
        }
    }

    var unsupportedIdentifier: String? {
        guard case let .unsupported(identifier) = self else { return nil }
        return identifier
    }

    var displayMessage: LocalizedMessage {
        if let unsupportedIdentifier {
            return L10n.message(
                "settings.language.unsupportedValue",
                arguments: [.string(unsupportedIdentifier)]
            )
        }
        switch self {
        case .followInterface:
            return L10n.message("settings.language.followInterface")
        case .zhHans:
            return L10n.message("settings.language.simplifiedChinese")
        case .en:
            return L10n.message("settings.language.english")
        case .unsupported:
            preconditionFailure("Unsupported identifiers return before static option resolution")
        }
    }

    func resolvedIdentifier(interfaceLocaleIdentifier: String) throws -> String {
        switch self {
        case .followInterface:
            interfaceLocaleIdentifier == "zh-Hans" ? "zh-Hans" : "en"
        case .zhHans:
            "zh-Hans"
        case .en:
            "en"
        case let .unsupported(identifier):
            throw RepositoryContentLanguageError.unsupported(identifier)
        }
    }
}

enum RepositoryContentLanguageError: Error, Equatable {
    case unsupported(String)
}

@Observable
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
        if let localized = localizedString(for: key, identifier: identifier, table: table, bundle: bundle) {
            return localized
        }
        if identifier != "en",
           let english = localizedString(for: key, identifier: "en", table: table, bundle: bundle) {
            return english
        }
        return fallback ?? key
    }

    private func localizedString(
        for key: String,
        identifier: String,
        table: String?,
        bundle: Bundle
    ) -> String? {
        guard let path = bundle.path(forResource: identifier, ofType: "lproj"),
              let localizedBundle = Bundle(path: path)
        else { return nil }

        let missingMarker = "___AREAMATRIX_MISSING_L10N_MARKER___"
        let value = localizedBundle.localizedString(forKey: key, value: missingMarker, table: table)
        return value == missingMarker ? nil : value
    }
}

enum VerbatimReason: String, Codable, Equatable {
    case brand
    case filesystemPath
    case languageGlyph
    case technicalDetail
    case technicalIdentifier
    case userContent
}

enum LocalizedArgument: Codable, Equatable {
    case string(String)
    case integer(Int)
    case integer64(Int64)
    case double(Double)

    var value: CVarArg {
        switch self {
        case let .string(value): value
        case let .integer(value): value
        case let .integer64(value): value
        case let .double(value): value
        }
    }
}

struct LocalizedMessage: Codable, Equatable {
    let key: String
    let arguments: [LocalizedArgument]
    let pluralCount: Int64?
    let fallback: String?
    let technicalDetail: String?

    init(
        key: String,
        arguments: [LocalizedArgument] = [],
        pluralCount: Int64? = nil,
        fallback: String? = nil,
        technicalDetail: String? = nil
    ) {
        self.key = key
        self.arguments = arguments
        self.pluralCount = pluralCount
        self.fallback = fallback
        self.technicalDetail = technicalDetail
    }
}

enum AppDisplayText: Codable, Equatable {
    case localized(LocalizedMessage)
    case verbatim(String, reason: VerbatimReason)

    var verbatimValue: String? {
        guard case let .verbatim(value, _) = self else { return nil }
        return value
    }
}

@MainActor
final class AppLanguageStore: ObservableObject {
    @Published private(set) var selection: AppLanguage

    private let defaults: UserDefaults
    private let defaultsKey: String
    private let localizer: AppLocalizer
    private let preferredLanguages: () -> [String]
    private var localeChangeObservation: AnyCancellable?

    init(
        defaults: UserDefaults = .standard,
        defaultsKey: String = AppLanguage.defaultsKey,
        runtime: AppLanguageRuntime = .shared,
        localizer: AppLocalizer? = nil,
        initialLanguageOverride: AppLanguage? = nil,
        preferredLanguages: @escaping () -> [String] = { Locale.preferredLanguages },
        notificationCenter: NotificationCenter = .default
    ) {
        self.defaults = defaults
        self.defaultsKey = defaultsKey
        self.localizer = localizer ?? AppLocalizer(runtime: runtime)
        self.preferredLanguages = preferredLanguages
        let initialSelection = initialLanguageOverride ?? AppLanguage(
            persistedValue: defaults.string(forKey: defaultsKey)
        )
        selection = initialSelection
        if initialLanguageOverride == nil {
            let persistedValue = defaults.string(forKey: defaultsKey)
            if let canonicalValue = AppLanguage.canonicalPersistedValue(for: persistedValue),
               canonicalValue != persistedValue {
                defaults.set(canonicalValue, forKey: defaultsKey)
            }
        }
        self.localizer.apply(initialSelection, preferredLanguages: preferredLanguages())
        localeChangeObservation = Publishers.Merge(
            notificationCenter.publisher(for: NSLocale.currentLocaleDidChangeNotification),
            notificationCenter.publisher(for: NSApplication.didBecomeActiveNotification)
        )
        .sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.systemLocaleDidChange()
            }
        }
    }

    var resolvedResourceLocaleIdentifier: String {
        localizer.resourceLocaleIdentifier
    }

    func select(_ language: AppLanguage) {
        guard language != selection else { return }
        defaults.set(language.rawValue, forKey: defaultsKey)
        localizer.apply(language, preferredLanguages: preferredLanguages())
        selection = language
    }

    func selectNext() {
        select(selection.next)
    }

    func localizedString(_ key: String) -> String {
        localizer.string(key)
    }

    private func systemLocaleDidChange() {
        guard selection == .system else { return }
        localizer.apply(.system, preferredLanguages: preferredLanguages())
        objectWillChange.send()
    }
}
