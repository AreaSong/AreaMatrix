import Foundation

enum ImportSingleFileFilenameValidator {
    private static let invalidScalars = CharacterSet(charactersIn: "/\\\\:*?\"<>|")

    static func validationMessage(for filename: String) -> String? {
        validationDisplayText(for: filename).map(L10n.resolve)
    }

    static func validationDisplayText(for filename: String) -> AppDisplayText? {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return L10n.display("import.filename.empty")
        }
        if trimmed == "." || trimmed == ".." {
            return L10n.display("import.filename.dotPath")
        }
        if trimmed.rangeOfCharacter(from: invalidScalars) != nil {
            return L10n.display("import.filename.invalidCharacters")
        }
        return nil
    }

    static func validate(_ filename: String) throws {
        if validationDisplayText(for: filename) != nil {
            throw AppSemanticError.invalidPath(rawContext: filename)
        }
    }
}

protocol SourcePreflightInspecting: Sendable {
    func inspect(sourceURL: URL) throws -> SourcePreflightSnapshot
}

struct SourcePreflightSnapshot {
    var sizeBytes: Int64
    var modifiedAt: Int64?
}

struct ImportSingleFilePreflightError: Error {
    var conflict: ImportSingleFileConflict
    var sourceSizeBytes: Int64?

    init(_ conflict: ImportSingleFileConflict, sourceSizeBytes: Int64?) {
        self.conflict = conflict
        self.sourceSizeBytes = sourceSizeBytes
    }
}

enum ImportSingleFilePreflightTarget {
    static func relativePath(category: String, filename: String) -> String {
        let cleanCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(cleanCategory.isEmpty ? "inbox" : cleanCategory)/\(cleanName.isEmpty ? "untitled" : cleanName)"
    }
}
