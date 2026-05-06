import Foundation
import XCTest
@testable import AreaMatrix

final class ImportSingleFilePreflightTests: XCTestCase {
    func testCorePreflightUsesSwiftFallbackWhenPreviewImportBindingIsMissing() async throws {
        let repoURL = try makeImportSingleFileTemporaryDirectory(prefix: "preflight-repo")
        let sourceRoot = try makeImportSingleFileTemporaryDirectory(prefix: "preflight-source")
        defer {
            try? FileManager.default.removeItem(at: repoURL)
            try? FileManager.default.removeItem(at: sourceRoot)
        }
        let sourceURL = sourceRoot.appendingPathComponent("source.pdf")
        try Data("new".utf8).write(to: sourceURL)

        try await CoreBridge().initializeEmptyRepository(repoPath: repoURL.path)
        let result = await CoreImportSingleFilePreflight().preflightSingleFileImport(request: .fixture(
            repoPath: repoURL.path,
            sourceURL: sourceURL,
            category: "docs",
            targetFilename: "source.pdf"
        ))

        XCTAssertEqual(result.sourceSizeBytes, 3)
        XCTAssertNotNil(result.hashSha256)
        XCTAssertEqual(result.targetRelativePath, "docs/source.pdf")
        XCTAssertEqual(result.replaceOptionVisibility, .hidden)
        XCTAssertEqual(result.conflict, .none)
        XCTAssertNil(result.importBlockingReason(isReplaceConfirmed: false))
    }

    func testCorePreflightUsesInjectedPreviewerResultWhenPreviewImportExists() async throws {
        let sourceRoot = try makeImportSingleFileTemporaryDirectory(prefix: "preflight-source")
        defer { try? FileManager.default.removeItem(at: sourceRoot) }
        let sourceURL = sourceRoot.appendingPathComponent("source.pdf")
        try Data("new".utf8).write(to: sourceURL)
        let result = ImportSingleFilePreflightResult(
            sourceSizeBytes: 3,
            hashSha256: "core-hash",
            targetRelativePath: "docs/source.pdf",
            conflict: .name(path: "docs/source.pdf"),
            replaceOptionVisibility: .enabled
        )

        let preflight = CoreImportSingleFilePreflight(previewer: StaticCoreImportPreviewer(result: result))
        let actual = await preflight.preflightSingleFileImport(request: .fixture(
            repoPath: "/tmp/repo",
            sourceURL: sourceURL,
            category: "docs",
            targetFilename: "source.pdf"
        ))

        XCTAssertEqual(actual, result)
        XCTAssertEqual(actual.importBlockingReason(isReplaceConfirmed: false), "请先完成 S1-23 conflict-name 处理")
    }

    func testCorePreflightDetectsDuplicateHashViaSwiftFallback() async throws {
        let repoURL = try makeImportSingleFileTemporaryDirectory(prefix: "preflight-repo")
        let sourceRoot = try makeImportSingleFileTemporaryDirectory(prefix: "preflight-source")
        defer {
            try? FileManager.default.removeItem(at: repoURL)
            try? FileManager.default.removeItem(at: sourceRoot)
        }

        let existingURL = sourceRoot.appendingPathComponent("existing.pdf")
        let incomingURL = sourceRoot.appendingPathComponent("incoming.pdf")
        let bytes = Data("same-bytes".utf8)
        try bytes.write(to: existingURL)
        try bytes.write(to: incomingURL)

        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        _ = try await bridge.importCopiedFile(
            repoPath: repoURL.path,
            sourceURL: existingURL,
            overrideCategory: "docs",
            overrideFilename: "existing.pdf"
        )

        let result = await CoreImportSingleFilePreflight().preflightSingleFileImport(request: .fixture(
            repoPath: repoURL.path,
            sourceURL: incomingURL,
            category: "docs",
            targetFilename: "incoming.pdf"
        ))

        XCTAssertEqual(result.conflict, .duplicate(existingPath: "docs/existing.pdf"))
        XCTAssertEqual(result.replaceOptionVisibility, .enabled)
        XCTAssertEqual(result.importBlockingReason(isReplaceConfirmed: false), "请先完成 S1-22 conflict-duplicate 处理")
    }

    func testCorePreflightDetectsSameNameConflictViaSwiftFallback() async throws {
        let repoURL = try makeImportSingleFileTemporaryDirectory(prefix: "preflight-repo")
        let sourceRoot = try makeImportSingleFileTemporaryDirectory(prefix: "preflight-source")
        defer {
            try? FileManager.default.removeItem(at: repoURL)
            try? FileManager.default.removeItem(at: sourceRoot)
        }

        let existingURL = sourceRoot.appendingPathComponent("existing.pdf")
        let incomingURL = sourceRoot.appendingPathComponent("incoming.pdf")
        try Data("old".utf8).write(to: existingURL)
        try Data("new".utf8).write(to: incomingURL)

        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        _ = try await bridge.importCopiedFile(
            repoPath: repoURL.path,
            sourceURL: existingURL,
            overrideCategory: "docs",
            overrideFilename: "shared.pdf"
        )

        let result = await CoreImportSingleFilePreflight().preflightSingleFileImport(request: .fixture(
            repoPath: repoURL.path,
            sourceURL: incomingURL,
            category: "docs",
            targetFilename: "shared.pdf"
        ))

        XCTAssertEqual(result.conflict, .name(path: "docs/shared.pdf"))
        XCTAssertEqual(result.replaceOptionVisibility, .enabled)
        XCTAssertEqual(result.importBlockingReason(isReplaceConfirmed: false), "请先完成 S1-23 conflict-name 处理")
    }

    func testCorePreflightRejectsInvalidTargetFilenameBeforeImport() async throws {
        let sourceRoot = try makeImportSingleFileTemporaryDirectory(prefix: "preflight-source")
        defer { try? FileManager.default.removeItem(at: sourceRoot) }
        let sourceURL = sourceRoot.appendingPathComponent("source.pdf")
        try Data("new".utf8).write(to: sourceURL)

        let result = await CoreImportSingleFilePreflight().preflightSingleFileImport(request: .fixture(
            repoPath: "/tmp/repo",
            sourceURL: sourceURL,
            category: "docs",
            targetFilename: "bad/name.pdf"
        ))

        XCTAssertEqual(result.hashSha256, nil)
        XCTAssertEqual(
            result.conflict,
            .invalidFilename("文件名不能包含 / \\ : * ? \" < > |")
        )
        XCTAssertEqual(
            result.importBlockingReason(isReplaceConfirmed: false),
            "文件名不能包含 / \\ : * ? \" < > |"
        )
    }

    func testCorePreflightBlocksICloudPlaceholderBeforeCorePreviewCall() async throws {
        let sourceRoot = try makeImportSingleFileTemporaryDirectory(prefix: "preflight-source")
        defer { try? FileManager.default.removeItem(at: sourceRoot) }
        let sourceURL = sourceRoot.appendingPathComponent("source.pdf.icloud")
        let previewer = StaticCoreImportPreviewer(result: .readyFixture())

        let result = await CoreImportSingleFilePreflight(previewer: previewer).preflightSingleFileImport(request: .fixture(
            repoPath: "/tmp/repo",
            sourceURL: sourceURL,
            category: "docs",
            targetFilename: "source.pdf"
        ))
        let requests = await previewer.recordedRequests()

        XCTAssertEqual(result.conflict, .iCloudPlaceholder(path: sourceURL.path))
        XCTAssertEqual(result.replaceOptionVisibility, .hidden)
        XCTAssertEqual(requests, [])
        XCTAssertEqual(result.importBlockingReason(isReplaceConfirmed: false), "iCloud placeholder 需要下载后才能导入")
    }
}

private actor StaticCoreImportPreviewer: CoreImportPreviewing {
    private let result: ImportSingleFilePreflightResult
    private var requests: [ImportSingleFilePreflightRequest] = []

    init(result: ImportSingleFilePreflightResult) {
        self.result = result
    }

    func previewSingleFileImport(
        request: ImportSingleFilePreflightRequest
    ) async throws -> ImportSingleFilePreflightResult {
        requests.append(request)
        return result
    }

    func recordedRequests() -> [ImportSingleFilePreflightRequest] {
        requests
    }
}

private extension ImportSingleFilePreflightRequest {
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
            targetFilename: targetFilename,
            allowReplaceDuringImport: true,
            isTrashAvailable: true
        )
    }
}

private extension ImportSingleFilePreflightResult {
    static func readyFixture() -> ImportSingleFilePreflightResult {
        ImportSingleFilePreflightResult(
            sourceSizeBytes: 12,
            hashSha256: "hash",
            targetRelativePath: "docs/source.pdf",
            conflict: .none,
            replaceOptionVisibility: .hidden
        )
    }
}
