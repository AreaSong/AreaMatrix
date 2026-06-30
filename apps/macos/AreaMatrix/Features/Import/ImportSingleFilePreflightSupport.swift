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
            throw CoreError.InvalidPath(path: filename)
        }
    }
}

struct LocalICloudPlaceholderDownloader: ICloudPlaceholderDownloading {
    func downloadPlaceholder(at sourceURL: URL) async throws {
        try FileManager.default.startDownloadingUbiquitousItem(at: sourceURL)
    }
}

struct SourcePreflightSnapshot {
    var sizeBytes: Int64
    var modifiedAt: Int64?

    static func inspect(sourceURL: URL) throws -> SourcePreflightSnapshot {
        if ImportSingleFilePreflightTarget.isICloudPlaceholder(sourceURL) {
            throw ImportSingleFilePreflightError(
                .iCloudPlaceholder(path: sourceURL.path),
                sourceSizeBytes: nil
            )
        }
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw ImportSingleFilePreflightError(
                .sourceUnavailable("来源文件已消失，请重试 preview"),
                sourceSizeBytes: nil
            )
        }
        guard FileManager.default.isReadableFile(atPath: sourceURL.path) else {
            throw ImportSingleFilePreflightError(
                .sourceUnavailable("来源文件不可读，请检查权限"),
                sourceSizeBytes: nil
            )
        }
        let values = try sourceURL.resourceValues(forKeys: [
            .fileSizeKey,
            .isRegularFileKey,
            .contentModificationDateKey
        ])
        guard values.isRegularFile == true else {
            throw ImportSingleFilePreflightError(
                .sourceUnavailable("只支持单文件导入"),
                sourceSizeBytes: nil
            )
        }
        return SourcePreflightSnapshot(
            sizeBytes: Int64(values.fileSize ?? 0),
            modifiedAt: values.contentModificationDate.map { Int64($0.timeIntervalSince1970) }
        )
    }
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

    static func isICloudPlaceholder(_ url: URL) -> Bool {
        if url.path.hasSuffix(".icloud") || url.path.contains(".icloud/") {
            return true
        }
        guard let values = try? url.resourceValues(forKeys: [
            .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey
        ]) else {
            return false
        }
        return values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus == .notDownloaded
    }
}
