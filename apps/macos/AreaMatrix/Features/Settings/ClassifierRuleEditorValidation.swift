import Foundation

enum ClassifierRuleValidationIssue: String, Equatable, Identifiable {
    case duplicateSlug
    case duplicateExtension
    case duplicateKeyword
    case invalidSlug
    case displayNameRequired
    case priorityOutOfRange
    case invalidExtension
    case invalidKeyword

    var id: String {
        rawValue
    }

    var displayText: String {
        switch self {
        case .duplicateSlug: L10n.string("settings.classifier.validation.issue.duplicateSlug")
        case .duplicateExtension: L10n.string("settings.classifier.validation.issue.duplicateExtension")
        case .duplicateKeyword: L10n.string("settings.classifier.validation.issue.duplicateKeyword")
        case .invalidSlug: L10n.string("settings.classifier.validation.issue.invalidSlug")
        case .displayNameRequired: L10n.string("settings.classifier.validation.issue.displayNameRequired")
        case .priorityOutOfRange: L10n.string("settings.classifier.validation.issue.priorityOutOfRange")
        case .invalidExtension: L10n.string("settings.classifier.validation.issue.invalidExtension")
        case .invalidKeyword: L10n.string("settings.classifier.validation.issue.invalidKeyword")
        }
    }
}

enum ClassifierRuleEditorValidation {
    static let priorityRange: ClosedRange<Int64> = -1000 ... 1000
    private static let slugPattern = #"^[a-z0-9][a-z0-9-]*$"#
    private static let extensionPattern = #"^[a-z0-9][a-z0-9_-]*$"#

    static func normalizedExtension(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
    }

    static func errors(
        for draft: ClassifierRuleEditorDraft,
        existingRules: [ClassifierRuleRecordSnapshot]
    ) -> [ClassifierRuleValidationIssue] {
        var errors = fieldErrors(for: draft)
        let duplicateSlug = existingRules.contains { $0.slug == draft.slug && $0.ruleID != draft.ruleID }
        if duplicateSlug { errors.append(.duplicateSlug) }
        if Set(draft.extensions).count != draft.extensions.count { errors.append(.duplicateExtension) }
        if Set(draft.keywords).count != draft.keywords.count { errors.append(.duplicateKeyword) }
        return errors
    }

    private static func fieldErrors(for draft: ClassifierRuleEditorDraft) -> [ClassifierRuleValidationIssue] {
        var errors: [ClassifierRuleValidationIssue] = []
        if draft.slug.isEmpty || !matches(draft.slug, pattern: slugPattern) { errors.append(.invalidSlug) }
        if draft.displayName.isEmpty { errors.append(.displayNameRequired) }
        if !priorityRange.contains(draft.priority) { errors.append(.priorityOutOfRange) }
        if draft.extensions.contains(where: { !matches($0, pattern: extensionPattern) }) {
            errors.append(.invalidExtension)
        }
        if draft.keywords.contains(where: { $0.isEmpty || $0.count > 80 }) {
            errors.append(.invalidKeyword)
        }
        return errors
    }

    private static func matches(_ value: String, pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }
}
