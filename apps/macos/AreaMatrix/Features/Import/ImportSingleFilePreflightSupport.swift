import Foundation

enum ImportSingleFileFilenameValidator {
    private static let invalidScalars = CharacterSet(charactersIn: "/\\\\:*?\"<>|")

    static func validationMessage(for filename: String) -> String? {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "文件名不能为空"
        }
        if trimmed == "." || trimmed == ".." {
            return "文件名不能是 . 或 .."
        }
        if trimmed.rangeOfCharacter(from: invalidScalars) != nil {
            return "文件名不能包含 / \\ : * ? \" < > |"
        }
        return nil
    }

    static func validate(_ filename: String) throws {
        if validationMessage(for: filename) != nil {
            throw AppSemanticError.invalidPath(rawContext: filename)
        }
    }
}

struct LocalICloudPlaceholderDownloader: ICloudPlaceholderDownloading {
    func downloadPlaceholder(at sourceURL: URL) async throws {
        try FileManager.default.startDownloadingUbiquitousItem(at: sourceURL)
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
