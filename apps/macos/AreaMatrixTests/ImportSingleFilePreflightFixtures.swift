@testable import AreaMatrix
import Foundation

extension ImportSingleFilePreflightRequest {
    static func fixture(
        repoPath: String,
        sourceURL: URL,
        category: String,
        targetFilename: String
    ) -> ImportSingleFilePreflightRequest {
        ImportSingleFilePreflightRequest(
            repoPath: repoPath,
            sourceURL: sourceURL,
            category: category,
            targetFilename: targetFilename
        )
    }
}

extension ImportSingleFilePreflightResult {
    static func importSingleFileReadyFixture(
        targetRelativePath: String = "docs/source.pdf"
    ) -> ImportSingleFilePreflightResult {
        ImportSingleFilePreflightResult(
            sourceSizeBytes: 12,
            hashSha256: "hash",
            targetRelativePath: targetRelativePath,
            conflict: .none
        )
    }

    static func importICloudPlaceholderFixture(
        path: String = importSingleFileSourcePath(),
        targetRelativePath: String = "docs/source.pdf"
    ) -> ImportSingleFilePreflightResult {
        ImportSingleFilePreflightResult(
            sourceSizeBytes: nil,
            hashSha256: nil,
            targetRelativePath: targetRelativePath,
            conflict: .iCloudPlaceholder(path: path)
        )
    }

    static func importHiddenDuplicateFixture() -> ImportSingleFilePreflightResult {
        ImportSingleFilePreflightResult(
            sourceSizeBytes: 12,
            hashSha256: "hash",
            targetRelativePath: "docs/source.pdf",
            conflict: .duplicate(existingPath: "docs/source.pdf")
        )
    }

    static func importDuplicateFixture() -> ImportSingleFilePreflightResult {
        ImportSingleFilePreflightResult(
            sourceSizeBytes: 12,
            hashSha256: "duplicate-hash",
            targetRelativePath: "docs/source.pdf",
            conflict: .duplicate(existingPath: "docs/existing.pdf"),
            keepBothTargetRelativePath: "docs/source_1.pdf"
        )
    }

    static func importDuplicateReplaceFixture(
        targetRelativePath: String? = nil,
        existingPath: String? = nil,
        keepBothTargetRelativePath: String = "docs/reports/报告_1.pdf",
        existingFile: FileEntrySnapshot = .importDuplicateReplaceFixture()
    ) -> ImportSingleFilePreflightResult {
        let targetPath = targetRelativePath ?? existingFile.path
        return ImportSingleFilePreflightResult(
            sourceSizeBytes: 912 * 1024,
            sourceModifiedAt: 1_777_445_400,
            hashSha256: "duplicate-hash",
            targetRelativePath: targetPath,
            conflict: .duplicate(existingPath: existingPath ?? existingFile.path),
            keepBothTargetRelativePath: keepBothTargetRelativePath,
            existingFile: existingFile
        )
    }

    static func importNameConflictFixture() -> ImportSingleFilePreflightResult {
        ImportSingleFilePreflightResult(
            sourceSizeBytes: 12,
            hashSha256: "incoming-hash",
            targetRelativePath: "docs/source.pdf",
            conflict: .name(path: "docs/source.pdf"),
            keepBothTargetRelativePath: "docs/source_1.pdf",
            existingPaths: ["docs/source.pdf", "docs/source_1.pdf"]
        )
    }

    static func importNameConflictReplaceFixture(
        targetRelativePath: String? = nil,
        existingPath: String? = nil,
        keepBothTargetRelativePath: String = "docs/reports/报告_1.pdf",
        existingPaths: Set<String>? = nil,
        existingFile: FileEntrySnapshot = .importNameConflictReplaceFixture()
    ) -> ImportSingleFilePreflightResult {
        let targetPath = targetRelativePath ?? existingFile.path
        return ImportSingleFilePreflightResult(
            sourceSizeBytes: 912 * 1024,
            sourceModifiedAt: 1_777_445_400,
            hashSha256: "incoming-hash",
            targetRelativePath: targetPath,
            conflict: .name(path: existingPath ?? existingFile.path),
            keepBothTargetRelativePath: keepBothTargetRelativePath,
            existingPaths: existingPaths ?? [existingFile.path],
            existingFile: existingFile
        )
    }
}
