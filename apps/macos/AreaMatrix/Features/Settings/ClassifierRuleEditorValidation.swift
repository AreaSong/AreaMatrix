import Foundation

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
    ) -> [String] {
        var errors = fieldErrors(for: draft)
        let duplicateSlug = existingRules.contains { $0.slug == draft.slug && $0.ruleID != draft.ruleID }
        if duplicateSlug { errors.append("slug duplicate") }
        if Set(draft.extensions).count != draft.extensions.count { errors.append("duplicate extension") }
        if Set(draft.keywords).count != draft.keywords.count { errors.append("duplicate keyword") }
        return errors
    }

    private static func fieldErrors(for draft: ClassifierRuleEditorDraft) -> [String] {
        var errors: [String] = []
        if draft.slug.isEmpty || !matches(draft.slug, pattern: slugPattern) { errors.append("invalid slug") }
        if draft.displayName.isEmpty { errors.append("display name required") }
        if !priorityRange.contains(draft.priority) { errors.append("priority out of range") }
        if draft.extensions.contains(where: { !matches($0, pattern: extensionPattern) }) {
            errors.append("invalid extension")
        }
        if draft.keywords.contains(where: { $0.isEmpty || $0.count > 80 }) {
            errors.append("invalid keyword")
        }
        return errors
    }

    private static func matches(_ value: String, pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }
}
