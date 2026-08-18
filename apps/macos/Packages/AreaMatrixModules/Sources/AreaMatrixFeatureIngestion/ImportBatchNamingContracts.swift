import Foundation

public enum ImportBatchNamingStrategy: String, CaseIterable, Identifiable, Sendable {
    case suggestedName
    case originalName
    case normalizedCharacters
    case uniformPrefix

    public var id: String {
        rawValue
    }
}

public extension String {
    var importBatchNormalizedFilename: String {
        let invalidScalars = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let normalized = precomposedStringWithCanonicalMapping
        return normalized.map { character in
            String(character).rangeOfCharacter(from: invalidScalars) == nil ? character : "-"
        }
        .map(String.init)
        .joined()
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
