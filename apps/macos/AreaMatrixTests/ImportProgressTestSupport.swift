@testable import AreaMatrix
import XCTest

func importProgressRepoPath() -> String {
    "/tmp/repo"
}

func importProgressSourcePath() -> String {
    "/tmp/source.pdf"
}

extension OnboardingModel {
    var currentImportProgressState: ImportProgressRouteState? {
        guard case let .importProgress(state) = route else { return nil }
        return state
    }
}

enum ImportProgressTestFixtures {
    static let runningCopyProgress = ImportBatchProgressSnapshot(
        completed: 1,
        failed: 0,
        total: 3,
        remaining: 2,
        currentPath: "docs/contract.pdf",
        items: [
            .init(
                sourcePath: "/tmp/invoice.pdf",
                targetPath: "finance/invoice.pdf",
                phase: .done,
                errorMessage: nil
            ),
            .init(
                sourcePath: "/tmp/contract.pdf",
                targetPath: "docs/contract.pdf",
                phase: .copying,
                errorMessage: nil
            ),
            .init(
                sourcePath: "/tmp/later.pdf",
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
                sourcePath: "/tmp/invoice.pdf",
                targetPath: "finance/invoice.pdf",
                phase: .done,
                errorMessage: nil
            ),
            .init(
                sourcePath: "/tmp/contract.pdf",
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
        sourcePath: "/tmp/external.pdf",
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
                sourcePath: "/tmp/invoice.pdf",
                targetPath: "finance/invoice.pdf",
                phase: .done,
                errorMessage: nil
            ),
            .init(
                sourcePath: "/tmp/合同.pdf",
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

@MainActor
func waitForImportResultRoute(
    _ model: OnboardingModel,
    file: StaticString = #filePath,
    line: UInt = #line
) async -> ImportResultRouteState? {
    for _ in 0 ..< 100 {
        if case let .importResult(state) = model.route { return state }
        await Task.yield()
    }
    XCTFail("Timed out waiting for import result route, got \(model.route)", file: file, line: line)
    return nil
}

actor StaticImportBatchSessionStore: ImportBatchSessionPersisting {
    private let session: ImportBatchSessionSnapshot?
    private var cleared: [String] = []

    init(session: ImportBatchSessionSnapshot?) {
        self.session = session
    }

    func saveSession(_: ImportBatchSessionSnapshot) async {}

    func loadSession(repoPath: String) async -> ImportBatchSessionSnapshot? {
        guard session?.repoPath == repoPath else { return nil }
        return session
    }

    func clearSession(repoPath: String) {
        cleared.append(repoPath)
    }

    func clearedRepoPaths() -> [String] {
        cleared
    }
}

actor RecordingImportBatchSessionStore: ImportBatchSessionPersisting {
    private var saved: [ImportBatchSessionSnapshot] = []
    private var cleared: [String] = []
    private var sessionsByRepoPath: [String: ImportBatchSessionSnapshot] = [:]

    func saveSession(_ session: ImportBatchSessionSnapshot) async {
        saved.append(session)
        sessionsByRepoPath[session.repoPath] = session
    }

    func loadSession(repoPath: String) async -> ImportBatchSessionSnapshot? {
        sessionsByRepoPath[repoPath]
    }

    func clearSession(repoPath: String) async {
        cleared.append(repoPath)
        sessionsByRepoPath[repoPath] = nil
    }

    func savedSessions() -> [ImportBatchSessionSnapshot] {
        saved
    }

    func clearedRepoPaths() -> [String] {
        cleared
    }
}

actor ImportProgressFatalCopyErrorMapper: CoreErrorMapping {
    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        switch error {
        case .Io: .importProgressFatalCopyError
        default: .importSingleFileError(kind: .internal)
        }
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
