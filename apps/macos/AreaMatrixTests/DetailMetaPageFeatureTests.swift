import XCTest
@testable import AreaMatrix

final class DetailMetaPageFeatureTests: XCTestCase {
    @MainActor
    func testS112ShowsCachedMetadataImmediatelyBeforeC112RefreshCompletes() async {
        let cached = FileEntrySnapshot.detailMetaFixture(id: 12, currentName: "cached.pdf")
        let refreshed = FileEntrySnapshot.detailMetaFixture(id: 12, currentName: "refreshed.pdf")
        let detailer = DetailMetaSuspendedDetailer(result: .success(refreshed))
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [cached]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: detailer,
            errorMapper: DetailMetaErrorMapper(mapping: .detailMetaFileNotFound())
        )

        let selectionTask = Task { await model.selectFiles([cached.id]) }
        await detailer.waitForRequest()

        XCTAssertEqual(model.selection, .single(cached.id))
        XCTAssertEqual(model.selectedFileDetail, cached)
        XCTAssertTrue(model.isDetailLoading)

        await detailer.finish()
        await selectionTask.value

        XCTAssertEqual(model.selectedFileDetail, refreshed)
        XCTAssertEqual(model.files, [refreshed])
        XCTAssertFalse(model.isDetailLoading)
        XCTAssertNil(model.detailErrorMapping)
    }

    @MainActor
    func testS112KeepsCachedSummaryWhenC112GetFileFails() async {
        let cached = FileEntrySnapshot.detailMetaFixture(id: 13, currentName: "missing.pdf")
        let mapping = CoreErrorMappingSnapshot.detailMetaFileNotFound()
        let mapper = DetailMetaErrorMapper(mapping: mapping)
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [cached]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .failure(CoreError.FileNotFound(path: cached.path))),
            errorMapper: mapper
        )

        await model.selectFiles([cached.id])
        let mappedErrors = await mapper.recordedErrors()

        XCTAssertEqual(model.selectedFileDetail, cached)
        XCTAssertEqual(model.detailErrorMapping, mapping)
        XCTAssertEqual(mappedErrors, [CoreError.FileNotFound(path: cached.path)])
        XCTAssertFalse(model.isDetailLoading)
    }

    func testS112MetadataRowsIncludeC112SourceAndStatus() {
        let indexed = FileEntrySnapshot.detailMetaFixture(
            id: 14,
            currentName: "indexed.pdf",
            storageMode: "Indexed",
            sourcePath: "~/Downloads/indexed.pdf"
        )

        let rows = detailMetaMetadataRows(for: indexed)

        XCTAssertEqual(rows.value(for: "Source"), "~/Downloads/indexed.pdf")
        XCTAssertEqual(rows.value(for: "Status"), "Index-only")
    }

    func testS112MetadataRowsUseFallbackForMissingC112Source() {
        let detail = FileEntrySnapshot.detailMetaFixture(id: 15, currentName: "no-source.pdf", sourcePath: nil)

        XCTAssertEqual(detailMetaMetadataRows(for: detail).value(for: "Source"), "Not available")
    }
}

private actor DetailMetaNoopLister: CoreFileListing {
    func listFiles(repoPath: String, filter: FileFilterSnapshot) async throws -> [FileEntrySnapshot] {
        []
    }
}

private actor DetailMetaImmediateDetailer: CoreFileDetailing {
    enum Result {
        case success(FileEntrySnapshot)
        case failure(Error)
    }

    private let result: Result

    init(result: Result) {
        self.result = result
    }

    func getFile(repoPath: String, fileID: Int64) async throws -> FileEntrySnapshot {
        switch result {
        case .success(let file):
            return file
        case .failure(let error):
            throw error
        }
    }
}

private actor DetailMetaSuspendedDetailer: CoreFileDetailing {
    typealias Result = DetailMetaImmediateDetailer.Result

    private let result: Result
    private var continuation: CheckedContinuation<Void, Never>?
    private var didReceiveRequest = false

    init(result: Result) {
        self.result = result
    }

    func getFile(repoPath: String, fileID: Int64) async throws -> FileEntrySnapshot {
        didReceiveRequest = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        switch result {
        case .success(let file):
            return file
        case .failure(let error):
            throw error
        }
    }

    func waitForRequest() async {
        while !didReceiveRequest {
            await Task.yield()
        }
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}

private actor DetailMetaErrorMapper: CoreErrorMapping {
    private let mapping: CoreErrorMappingSnapshot
    private var errors: [CoreError] = []

    init(mapping: CoreErrorMappingSnapshot) {
        self.mapping = mapping
    }

    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        errors.append(error)
        return mapping
    }

    func recordedErrors() -> [CoreError] { errors }
}

private extension RepositoryOpeningResult {
    static func detailMetaFixture(repoPath: String, files: [FileEntrySnapshot]) -> RepositoryOpeningResult {
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
                displayName: "Repository",
                fileCount: Int64(files.count),
                children: []
            ),
            currentCategoryFiles: files
        )
    }
}

private extension FileEntrySnapshot {
    static func detailMetaFixture(
        id: Int64,
        currentName: String,
        storageMode: String = "Copied",
        sourcePath: String? = "~/Downloads/source.pdf"
    ) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: "docs/contracts/\(currentName)",
            originalName: currentName,
            currentName: currentName,
            category: "docs",
            sizeBytes: 256,
            hashSha256: "detail-meta-\(id)",
            storageMode: storageMode,
            origin: "Imported",
            sourcePath: sourcePath,
            importedAt: 1_700_000_000,
            updatedAt: 1_700_000_100
        )
    }
}

private extension [DetailMetaMetadataRow] {
    func value(for label: String) -> String? {
        first { $0.label == label }?.value
    }
}

private extension CoreErrorMappingSnapshot {
    static func detailMetaFileNotFound() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .fileNotFound,
            userMessage: "文件不存在",
            severity: .medium,
            suggestedAction: "刷新当前列表，确认文件是否已被移动或删除。",
            recoverability: .refreshRequired,
            rawContext: "S1-12 C1-12 get_file"
        )
    }
}
