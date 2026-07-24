import Foundation

enum L10n {
    static func display(_ key: String, fallback: String? = nil, technicalDetail: String? = nil) -> AppDisplayText {
        .localized(message(key, fallback: fallback, technicalDetail: technicalDetail))
    }

    static func display(
        _ key: String,
        arguments: [LocalizedArgument],
        fallback: String? = nil,
        technicalDetail: String? = nil
    ) -> AppDisplayText {
        .localized(message(
            key,
            arguments: arguments,
            fallback: fallback,
            technicalDetail: technicalDetail
        ))
    }

    /// Materializes an application-owned default at draft creation time.
    /// The returned value must not be refreshed after it becomes user-editable state.
    static func editableDefault(_ key: String, fallback: String? = nil) -> String {
        AppLanguageRuntime.shared.localizedString(key, fallback: fallback)
    }

    static func verbatim(_ value: String, reason: VerbatimReason) -> AppDisplayText {
        .verbatim(value, reason: reason)
    }

    static func resolve(_ message: LocalizedMessage) -> String {
        let localized = string(message.key, fallback: message.fallback)
        if let count = message.pluralCount {
            return String.localizedStringWithFormat(localized, count)
        }
        guard !message.arguments.isEmpty else { return localized }
        return String(
            format: localized,
            locale: Locale.autoupdatingCurrent,
            arguments: message.arguments.map(\.value)
        )
    }

    static func resolve(_ text: AppDisplayText) -> String {
        switch text {
        case let .localized(message):
            resolve(message)
        case let .verbatim(value, _):
            value
        }
    }

    static func message(
        _ key: String,
        fallback: String? = nil,
        technicalDetail: String? = nil
    ) -> LocalizedMessage {
        LocalizedMessage(key: key, fallback: fallback, technicalDetail: technicalDetail)
    }

    static func message(
        _ key: String,
        arguments: [LocalizedArgument],
        fallback: String? = nil,
        technicalDetail: String? = nil
    ) -> LocalizedMessage {
        LocalizedMessage(
            key: key,
            arguments: arguments,
            fallback: fallback,
            technicalDetail: technicalDetail
        )
    }

    static func pluralMessage(_ key: String, count: Int) -> LocalizedMessage {
        LocalizedMessage(key: key, pluralCount: Int64(count))
    }

    static func pluralMessage(_ key: String, count: Int64) -> LocalizedMessage {
        LocalizedMessage(key: key, pluralCount: count)
    }

    static func string(_ key: String, fallback: String? = nil) -> String {
        AppLanguageRuntime.shared.localizedString(key, fallback: fallback)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: Locale.autoupdatingCurrent, arguments: arguments)
    }

    static func plural(_ key: String, count: Int) -> String {
        String.localizedStringWithFormat(string(key), count)
    }

    static func plural(_ key: String, count: Int64) -> String {
        String.localizedStringWithFormat(string(key), count)
    }
}
