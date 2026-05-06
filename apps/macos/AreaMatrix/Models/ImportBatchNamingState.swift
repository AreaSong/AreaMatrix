import Foundation

enum ImportBatchNamingStrategy: String, CaseIterable, Identifiable, Sendable {
    case suggestedName
    case originalName
    case normalizedCharacters
    case uniformPrefix

    var id: String { rawValue }

    var title: String {
        switch self {
        case .suggestedName:
            return "使用建议命名"
        case .originalName:
            return "保留原名"
        case .normalizedCharacters:
            return "仅标准化字符"
        case .uniformPrefix:
            return "统一前缀"
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
