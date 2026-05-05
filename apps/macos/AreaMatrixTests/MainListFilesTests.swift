import XCTest
@testable import AreaMatrix

final class MainListFilesTests: XCTestCase {
    @MainActor
    func testMainListLoadsSelectedCategoryThroughC111ListFiles() async {
        let docsFile = FileEntrySnapshot.mainListFixture(
            id: 10,
            path: "docs/contracts/report.pdf",
            category: "docs",
            currentName: "report.pdf"
        )
        let lister = MainListRecordingFileLister(results: [.success([docsFile])])
        let model = MainFileListModel(
            opening: .mainListFixture(repoPath: "/tmp/repo", currentCategoryFiles: []),
            fileLister: lister,
            errorMapper: MainListRecordingErrorMapper(mapping: .mainListDbFixture(rawContext: "unused"))
        )

        await model.loadCurrentCategory("docs")
        let requests = await lister.recordedRequests()

        XCTAssertEqual(requests, [FileFilterSnapshot.currentCategory("docs")])
        XCTAssertEqual(model.files, [docsFile])
        XCTAssertNil(model.errorMapping)
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testMainListRetryKeepsCurrentCategoryFilter() async {
        let docsFile = FileEntrySnapshot.mainListFixture(
            id: 11,
            path: "docs/references/research.md",
            category: "docs",
            currentName: "research.md"
        )
        let lister = MainListRecordingFileLister(results: [.failure(CoreError.Db(message: "locked")), .success([docsFile])])
        let mapper = MainListRecordingErrorMapper(mapping: .mainListDbFixture(rawContext: "locked"))
        let model = MainFileListModel(
            opening: .mainListFixture(repoPath: "/tmp/repo", currentCategoryFiles: []),
            fileLister: lister,
            errorMapper: mapper
        )

        await model.loadCurrentCategory("docs")
        await model.retryCurrentCategory()
        let requests = await lister.recordedRequests()

        XCTAssertEqual(requests, [
            FileFilterSnapshot.currentCategory("docs"),
            FileFilterSnapshot.currentCategory("docs"),
        ])
        XCTAssertEqual(model.files, [docsFile])
        XCTAssertNil(model.errorMapping)
    }

    @MainActor
    func testMainListKeepsListFailureInline() async {
        let mapping = CoreErrorMappingSnapshot.mainListDbFixture(rawContext: "list db locked")
        let mapper = MainListRecordingErrorMapper(mapping: mapping)
        let model = MainFileListModel(
            opening: .mainListFixture(
                repoPath: "/tmp/repo",
                currentCategoryFiles: [.mainListFixture(id: 1, path: "inbox/a.txt", category: "inbox", currentName: "a.txt")]
            ),
            fileLister: MainListRecordingFileLister(results: [.failure(CoreError.Db(message: "list db locked"))]),
            errorMapper: mapper
        )

        await model.loadCurrentCategory("docs")
        let mappedErrors = await mapper.recordedErrors()

        XCTAssertEqual(model.files, [])
        XCTAssertEqual(model.errorMapping, mapping)
        XCTAssertEqual(mappedErrors, [CoreError.Db(message: "list db locked")])
        XCTAssertFalse(model.isLoading)
    }
}

private actor MainListRecordingFileLister: CoreFileListing {
    enum Result {
        case success([FileEntrySnapshot])
        case failure(Error)
    }

    private var results: [Result]
    private var requests: [FileFilterSnapshot] = []

    init(results: [Result]) {
        self.results = results
    }

    func listFiles(repoPath: String, filter: FileFilterSnapshot) async throws -> [FileEntrySnapshot] {
        requests.append(filter)
        guard !results.isEmpty else { return [] }

        switch results.removeFirst() {
        case .success(let files):
            return files
        case .failure(let error):
            throw error
        }
    }

    func recordedRequests() -> [FileFilterSnapshot] { requests }
}

private actor MainListRecordingErrorMapper: CoreErrorMapping {
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
    static func mainListFixture(
        repoPath: String,
        currentCategoryFiles: [FileEntrySnapshot]
    ) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .mainListFixture(repoPath: repoPath),
            tree: .mainListFixtureTree(),
            currentCategoryFiles: currentCategoryFiles
        )
    }
}

private extension RepoConfigSnapshot {
    static func mainListFixture(repoPath: String) -> RepoConfigSnapshot {
        RepoConfigSnapshot(
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
        )
    }
}

private extension RepositoryTreeNodeSnapshot {
    static func mainListFixtureTree() -> RepositoryTreeNodeSnapshot {
        RepositoryTreeNodeSnapshot(
            slug: "__root__",
            displayName: "资料库",
            kind: "RepositoryRoot",
            relativePath: "",
            fileCount: 0,
            depth: 0,
            children: [
                RepositoryTreeNodeSnapshot(
                    slug: "inbox",
                    displayName: "inbox",
                    fileCount: 1,
                    children: []
                ),
                RepositoryTreeNodeSnapshot(
                    slug: "docs",
                    displayName: "docs",
                    fileCount: 42,
                    children: []
                ),
            ]
        )
    }
}

private extension FileEntrySnapshot {
    static func mainListFixture(
        id: Int64,
        path: String,
        category: String,
        currentName: String
    ) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: path,
            originalName: currentName,
            currentName: currentName,
            category: category,
            sizeBytes: 128,
            hashSha256: "fixture-hash-\(id)",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000,
            updatedAt: 1_700_000_100
        )
    }
}

private extension CoreErrorMappingSnapshot {
    static func mainListDbFixture(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "当前列表不可用",
            severity: .high,
            suggestedAction: "请重试当前列表。",
            recoverability: .retryable,
            rawContext: rawContext
        )
    }
}
