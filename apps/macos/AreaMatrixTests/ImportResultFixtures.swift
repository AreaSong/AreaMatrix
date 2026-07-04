@testable import AreaMatrix

func importResultRepoPath() -> String {
    "/tmp/repo"
}

func importResultImportedFilename() -> String {
    "imported.pdf"
}

func importResultFailedFilename() -> String {
    "failed.pdf"
}

func importResultExistingFilename() -> String {
    "existing.pdf"
}

func importResultImportedSourcePath() -> String {
    "/tmp/\(importResultImportedFilename())"
}

func importResultFailedSourcePath() -> String {
    "/tmp/\(importResultFailedFilename())"
}

func importResultTargetPath(_ filename: String) -> String {
    "docs/\(filename)"
}

func importResultPrivateSourcePath(_ filename: String) -> String {
    "/Users/example/private/\(filename)"
}

func importResultExportFilename() -> String {
    "AreaMatrix-Import-Result.txt"
}

func importResultExportPath(suggestedFilename: String = importResultExportFilename()) -> String {
    "/tmp/\(suggestedFilename)"
}

func importResultSourceDetailJSON(sourcePath: String = importResultImportedSourcePath()) -> String {
    #"{"source":"\#(sourcePath)","mode":"copied","category":"docs"}"#
}

enum ImportResultFixtures {
    static let importedProgress = ImportBatchProgressSnapshot(
        completed: 1,
        failed: 0,
        total: 1,
        remaining: 0,
        currentPath: importResultTargetPath(importResultImportedFilename()),
        items: [
            ImportBatchProgressSnapshot.Item(
                fileID: 117,
                sourcePath: importResultImportedSourcePath(),
                targetPath: importResultTargetPath(importResultImportedFilename()),
                phase: .done,
                errorMessage: nil
            )
        ]
    )

    static let failedCopyProgress = ImportBatchProgressSnapshot(
        completed: 1,
        failed: 1,
        total: 2,
        remaining: 0,
        currentPath: importResultTargetPath(importResultFailedFilename()),
        items: [
            ImportBatchProgressSnapshot.Item(
                sourcePath: importResultImportedSourcePath(),
                targetPath: importResultTargetPath(importResultImportedFilename()),
                phase: .done,
                errorMessage: nil
            ),
            ImportBatchProgressSnapshot.Item(
                sourcePath: importResultFailedSourcePath(),
                targetPath: importResultTargetPath(importResultFailedFilename()),
                phase: .failed,
                errorMessage: "无访问权限"
            )
        ]
    )

    static let skippedDuplicateProgress = ImportBatchProgressSnapshot(
        completed: 1,
        failed: 0,
        total: 2,
        remaining: 0,
        currentPath: importResultTargetPath(importResultImportedFilename()),
        skipped: 1,
        items: [
            ImportBatchProgressSnapshot.Item(
                sourcePath: importResultPrivateSourcePath(importResultImportedFilename()),
                targetPath: importResultTargetPath(importResultImportedFilename()),
                phase: .done,
                errorMessage: nil
            ),
            ImportBatchProgressSnapshot.Item(
                sourcePath: importResultPrivateSourcePath(importResultExistingFilename()),
                targetPath: importResultTargetPath(importResultExistingFilename()),
                phase: .pending,
                errorMessage: "Duplicate skipped",
                existingRelativePath: importResultTargetPath(importResultExistingFilename())
            )
        ]
    )
}

extension ChangeLogEntrySnapshot {
    static func importResultFixture(
        id: Int64 = 1,
        filename: String = importResultImportedFilename(),
        detailJSON: String = importResultSourceDetailJSON()
    ) -> ChangeLogEntrySnapshot {
        ChangeLogEntrySnapshot(
            id: id,
            fileID: 10,
            filename: filename,
            category: "docs",
            action: "imported",
            detailJSON: detailJSON,
            occurredAt: 1_700_000_000
        )
    }
}
