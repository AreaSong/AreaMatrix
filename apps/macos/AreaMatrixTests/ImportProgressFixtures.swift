@testable import AreaMatrix
import Foundation

func importProgressRepoPath() -> String {
    "/tmp/repo"
}

func importProgressSourcePath() -> String {
    "/tmp/source.pdf"
}

func importProgressIndexSourcePath() -> String {
    importProgressBatchSourcePath("external.pdf")
}

func importProgressQueuedSourcePath(_ filename: String) -> String {
    "/tmp/source/\(filename)"
}

func importProgressBatchSourcePath(_ filename: String) -> String {
    "/tmp/\(filename)"
}

func importProgressBatchSourceURL(_ filename: String) -> URL {
    URL(fileURLWithPath: importProgressBatchSourcePath(filename))
}

enum ImportProgressFixtures {
    static let runningCopyProgress = ImportBatchProgressSnapshot(
        completed: 1,
        failed: 0,
        total: 3,
        remaining: 2,
        currentPath: "docs/contract.pdf",
        items: [
            .init(
                sourcePath: importProgressBatchSourcePath("invoice.pdf"),
                targetPath: "finance/invoice.pdf",
                phase: .done,
                errorMessage: nil
            ),
            .init(
                sourcePath: importProgressBatchSourcePath("contract.pdf"),
                targetPath: "docs/contract.pdf",
                phase: .copying,
                errorMessage: nil
            ),
            .init(
                sourcePath: importProgressBatchSourcePath("later.pdf"),
                targetPath: "docs/later.pdf",
                phase: .pending,
                errorMessage: nil
            )
        ]
    )

    static let failedCopyResultProgress = ImportBatchProgressSnapshot(
        completed: 1,
        failed: 1,
        total: 2,
        remaining: 0,
        currentPath: "docs/contract.pdf",
        items: [
            .init(
                sourcePath: importProgressBatchSourcePath("invoice.pdf"),
                targetPath: "finance/invoice.pdf",
                phase: .done,
                errorMessage: nil
            ),
            .init(
                sourcePath: importProgressBatchSourcePath("contract.pdf"),
                targetPath: "docs/contract.pdf",
                phase: .failed,
                errorMessage: "无访问权限"
            )
        ]
    )

    static let copyFailedProgress = failedProgress(
        sourcePath: importProgressSourcePath(),
        targetPath: "docs/copied.pdf",
        errorMessage: "文件读写失败"
    )

    static let moveFailedProgress = failedProgress(
        sourcePath: importProgressSourcePath(),
        targetPath: "docs/moved.pdf",
        errorMessage: "文件读写失败"
    )

    static let indexFailedProgress = failedProgress(
        sourcePath: importProgressIndexSourcePath(),
        targetPath: "docs/indexed.pdf",
        errorMessage: "文件不存在"
    )

    static let partialResultProgress = ImportBatchProgressSnapshot(
        completed: 1,
        failed: 1,
        total: 2,
        remaining: 0,
        currentPath: "finance/合同.pdf",
        items: [
            .init(
                sourcePath: importProgressBatchSourcePath("invoice.pdf"),
                targetPath: "finance/invoice.pdf",
                phase: .done,
                errorMessage: nil
            ),
            .init(
                sourcePath: importProgressBatchSourcePath("合同.pdf"),
                targetPath: "finance/合同.pdf",
                phase: .failed,
                errorMessage: "无访问权限"
            )
        ]
    )

    static func copyRetryContext(
        sourcePath: String,
        overrideFilename: String = "copied.pdf"
    ) -> ImportProgressRetryContext {
        retryContext(sourcePath: sourcePath, storageMode: .copy, overrideFilename: overrideFilename)
    }

    static func moveRetryContext(sourcePath: String) -> ImportProgressRetryContext {
        retryContext(sourcePath: sourcePath, storageMode: .move, overrideFilename: "moved.pdf")
    }

    static func indexRetryContext(sourcePath: String) -> ImportProgressRetryContext {
        retryContext(
            sourcePath: sourcePath,
            storageMode: .indexOnly,
            overrideFilename: "indexed.pdf",
            duplicateStrategy: .keepBoth
        )
    }

    private static func failedProgress(
        sourcePath: String,
        targetPath: String,
        errorMessage: String
    ) -> ImportBatchProgressSnapshot {
        ImportBatchProgressSnapshot(
            completed: 0,
            failed: 1,
            total: 1,
            remaining: 0,
            currentPath: targetPath,
            items: [
                .init(
                    sourcePath: sourcePath,
                    targetPath: targetPath,
                    phase: .failed,
                    errorMessage: errorMessage
                )
            ]
        )
    }

    private static func retryContext(
        sourcePath: String,
        storageMode: ImportSingleFileStorageMode,
        overrideFilename: String,
        duplicateStrategy: ImportProgressDuplicateStrategy = .ask
    ) -> ImportProgressRetryContext {
        ImportProgressRetryContext(
            repoPath: importProgressRepoPath(),
            sourcePath: sourcePath,
            storageMode: storageMode,
            overrideCategory: "docs",
            overrideFilename: overrideFilename,
            duplicateStrategy: duplicateStrategy
        )
    }
}

extension CoreErrorMappingSnapshot {
    static var importProgressFatalCopyError: CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .io,
            userMessage: "文件读写失败",
            severity: .critical,
            suggestedAction: "AreaMatrix 会先确认 staging 状态，再允许重试当前项。",
            recoverability: .fatal,
            rawContext: "import-progress fatal copy retry"
        )
    }

    static func importProgressFatalImportError(kind: CoreErrorKindSnapshot) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: kind,
            userMessage: importProgressFatalMessage(for: kind),
            severity: .critical,
            suggestedAction: "AreaMatrix 会先确认 staging 状态，再允许重试当前项。",
            recoverability: .fatal,
            rawContext: "import-progress fatal import progress"
        )
    }

    private static func importProgressFatalMessage(for kind: CoreErrorKindSnapshot) -> String {
        switch kind {
        case .io:
            "文件读写失败"
        case .fileNotFound:
            "文件不存在"
        default:
            "导入队列无法继续"
        }
    }
}
