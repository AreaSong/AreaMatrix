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

enum ImportSingleFilePreflightPolicy {
    static func isImportable(_ result: ImportSingleFilePreflightResult) -> Bool {
        switch result.conflict {
        case .none, .duplicate, .name:
            true
        case .invalidFilename, .iCloudPlaceholder, .iCloudDownloadFailed, .corePreviewUnavailable,
             .sourceUnavailable, .error:
            false
        }
    }
}

enum ImportSingleFilePreviewFailurePolicy {
    static func displayText(for error: Error) -> AppDisplayText {
        guard let context = CoreErrorRawContextSnapshot(error) else {
            return L10n.display("import.preview.categoryUnavailable")
        }

        switch context.kind {
        case .config:
            return L10n.display(
                "import.preview.invalidRules",
                arguments: [.string(context.rawContext)],
                technicalDetail: context.rawContext
            )
        case .classify:
            return L10n.display(
                "import.preview.category-unavailable",
                arguments: [.string(context.rawContext)],
                technicalDetail: context.rawContext
            )
        default:
            return L10n.display("import.preview.categoryUnavailable", technicalDetail: context.rawContext)
        }
    }
}
