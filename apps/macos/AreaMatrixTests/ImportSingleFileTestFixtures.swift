@testable import AreaMatrix
import Foundation
import XCTest

extension ClassifyResultSnapshot {
    static func s117Fixture() -> ClassifyResultSnapshot {
        makeImportSingleFileFixture()
    }

    static func importSingleFileFixture() -> ClassifyResultSnapshot {
        makeImportSingleFileFixture()
    }

    private static func makeImportSingleFileFixture() -> ClassifyResultSnapshot {
        ClassifyResultSnapshot(
            category: "docs",
            suggestedName: "source.pdf",
            reason: .extension,
            confidence: 0.7
        )
    }
}

extension FileEntrySnapshot {
    static func s117Fixture(
        currentName: String,
        category: String,
        hashSha256: String = "hash",
        storageMode: String = "Copied"
    ) -> FileEntrySnapshot {
        makeImportSingleFileFixture(
            id: 117,
            currentName: currentName,
            category: category,
            hashSha256: hashSha256,
            storageMode: storageMode
        )
    }

    static func importSingleFileFixture(
        currentName: String,
        category: String,
        hashSha256: String = "hash",
        storageMode: String = "Copied"
    ) -> FileEntrySnapshot {
        makeImportSingleFileFixture(
            id: 42,
            currentName: currentName,
            category: category,
            hashSha256: hashSha256,
            storageMode: storageMode
        )
    }

    private static func makeImportSingleFileFixture(
        id: Int64,
        currentName: String,
        category: String,
        hashSha256: String,
        storageMode: String
    ) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: "\(category)/\(currentName)",
            originalName: "source.pdf",
            currentName: currentName,
            category: category,
            sizeBytes: 12,
            hashSha256: hashSha256,
            storageMode: storageMode,
            origin: "Imported",
            sourcePath: "/tmp/source.pdf",
            importedAt: 1_700_000_000,
            updatedAt: 1_700_000_000
        )
    }
}

extension ImportEntryRequest {
    static func s117ImportRequest() -> ImportEntryRequest {
        ImportEntryRequest(
            repoPath: "/tmp/repo",
            source: .filePicker,
            destination: .autoClassify,
            urls: [URL(fileURLWithPath: "/tmp/source.pdf")],
            kind: .singleFile
        )
    }

    static func importSingleFileFixture(
        allowReplaceDuringImport: Bool = true,
        isTrashAvailable: Bool = true
    ) -> ImportEntryRequest {
        ImportEntryRequest(
            repoPath: "/tmp/repo",
            source: .filePicker,
            destination: .autoClassify,
            urls: [URL(fileURLWithPath: "/tmp/source.pdf")],
            kind: .singleFile,
            allowReplaceDuringImport: allowReplaceDuringImport,
            isTrashAvailable: isTrashAvailable
        )
    }
}

extension CoreErrorMappingSnapshot {
    static func s117Error(kind: CoreErrorKindSnapshot) -> CoreErrorMappingSnapshot {
        makeImportSingleFileError(
            kind: kind,
            suggestedAction: "Resolve the conflict and retry.",
            rawContext: "S1-17 import-single-sheet"
        )
    }

    static func importCopyFixture(kind: CoreErrorKindSnapshot) -> CoreErrorMappingSnapshot {
        makeImportSingleFileError(
            kind: kind,
            suggestedAction: "Choose a different file or resolve the conflict.",
            rawContext: "copy import"
        )
    }

    private static func makeImportSingleFileError(
        kind: CoreErrorKindSnapshot,
        suggestedAction: String,
        rawContext: String
    ) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: kind,
            userMessage: importErrorMessage(for: kind),
            severity: .high,
            suggestedAction: suggestedAction,
            recoverability: .userActionRequired,
            rawContext: rawContext
        )
    }

    // swiftlint:disable:next cyclomatic_complexity
    private static func importErrorMessage(for kind: CoreErrorKindSnapshot) -> String {
        switch kind {
        case .duplicateFile:
            "检测到重复文件"
        case .invalidPath:
            "路径无效"
        case .permissionDenied:
            "无访问权限"
        case .iCloudPlaceholder:
            "iCloud 文件尚未下载"
        case .io:
            "文件读写失败"
        case .db:
            "数据库错误"
        case .fileNotFound:
            "文件不存在"
        case .config:
            "配置不可用"
        case .classify:
            "分类失败"
        case .conflict:
            "命名冲突未解决"
        case .repoNotInitialized:
            "资料库尚未初始化"
        case .internal:
            "内部错误"
        }
    }
}

extension ImportSingleFileStorageMode {
    var coreStorageMode: String {
        switch self {
        case .copy:
            "Copied"
        case .move:
            "Moved"
        case .indexOnly:
            "Indexed"
        }
    }
}

extension RepositoryOpeningResult {
    static func s117Fixture(repoPath: String) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: RepoConfigSnapshot(
                repoPath: repoPath,
                defaultMode: "Copied",
                overviewOutput: "GeneratedOnly",
                aiEnabled: false,
                locale: "zh-Hans",
                iCloudWarn: true,
                enableExtensionRules: true,
                enableKeywordRules: true,
                fallbackToInbox: true,
                allowReplaceDuringImport: false
            ),
            tree: RepositoryTreeNodeSnapshot(
                slug: "__root__",
                displayName: "资料库",
                fileCount: 0,
                children: [
                    RepositoryTreeNodeSnapshot(slug: "inbox", displayName: "inbox", fileCount: 0, children: []),
                    RepositoryTreeNodeSnapshot(slug: "docs", displayName: "docs", fileCount: 0, children: []),
                    RepositoryTreeNodeSnapshot(
                        slug: "finance",
                        displayName: "finance",
                        fileCount: 0,
                        children: []
                    )
                ]
            ),
            currentCategoryFiles: []
        )
    }
}

func makeImportSingleFileTemporaryDirectory(prefix: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixImportSingleFile-\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@MainActor
func waitForImportSingleFilePreflightToSettle(
    _ model: ImportSingleFilePreviewModel,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    for _ in 0 ..< 100 {
        if !model.preflightStatus.isChecking {
            return
        }
        await Task.yield()
    }
    XCTFail("Timed out waiting for import preflight to settle", file: file, line: line)
}

@MainActor
func importS117Mode(
    model: ImportSingleFilePreviewModel,
    request: ImportEntryRequest,
    mode: ImportSingleFileStorageMode,
    name: String,
    storageMode: String
) async {
    if mode != .copy {
        await model.load(request: request)
    }
    model.selectedCategory = " finance "
    model.selectedStorageMode = mode
    model.suggestedName = " \(name) "
    await waitForImportSingleFilePreflightToSettle(model)
    let imported = await model.importSelectedFile()
    XCTAssertEqual(imported?.storageMode, storageMode)
}

func s117CoreCapabilityRequest() -> ImportEntryRequest {
    ImportEntryRequest(
        repoPath: "/tmp/repo",
        source: .filePicker,
        destination: .autoClassify,
        urls: [URL(fileURLWithPath: "/tmp/合同.pdf")],
        kind: .singleFile
    )
}

func s117CoreCapabilityPrediction() -> ClassifyResultSnapshot {
    ClassifyResultSnapshot(
        category: "docs",
        suggestedName: "2026Q1_合同.pdf",
        reason: .keyword,
        confidence: 0.93
    )
}

func s117CoreCapabilityImportRequests() -> [S117ImportRequest] {
    [
        s117ImportRequest(mode: .copy, filename: "copy.pdf"),
        s117ImportRequest(mode: .move, filename: "move.pdf"),
        s117ImportRequest(mode: .indexOnly, filename: "indexed.pdf")
    ]
}

func s117ImportRequest(
    mode: ImportSingleFileStorageMode,
    filename: String
) -> S117ImportRequest {
    S117ImportRequest(
        mode: mode,
        overrideCategory: "finance",
        overrideFilename: filename,
        duplicateStrategy: .ask
    )
}
