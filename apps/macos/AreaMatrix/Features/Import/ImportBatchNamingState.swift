import Foundation

enum ImportBatchNamingStrategy: String, CaseIterable, Identifiable {
    case suggestedName
    case originalName
    case normalizedCharacters
    case uniformPrefix

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .suggestedName:
            L10n.string("使用建议命名")
        case .originalName:
            L10n.string("保留原名")
        case .normalizedCharacters:
            L10n.string("仅标准化字符")
        case .uniformPrefix:
            L10n.string("统一前缀")
        }
    }
}

extension String {
    var importBatchNormalizedFilename: String {
        let invalidScalars = CharacterSet(charactersIn: "/\\\\:*?\"<>|")
        let normalized = precomposedStringWithCanonicalMapping
        return normalized.map { character in
            String(character).rangeOfCharacter(from: invalidScalars) == nil ? character : "-"
        }
        .map(String.init)
        .joined()
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
