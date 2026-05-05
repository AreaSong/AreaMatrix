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
            fileDetailer: MainListRecordingFileDetailer(results: []),
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
            fileDetailer: MainListRecordingFileDetailer(results: []),
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
            fileDetailer: MainListRecordingFileDetailer(results: []),
            errorMapper: mapper
        )

        await model.loadCurrentCategory("docs")
        let mappedErrors = await mapper.recordedErrors()

        XCTAssertEqual(model.files, [])
        XCTAssertEqual(model.errorMapping, mapping)
        XCTAssertEqual(mappedErrors, [CoreError.Db(message: "list db locked")])
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testMainListLoadsSelectedFileDetailThroughC112GetFile() async {
        let detail = FileEntrySnapshot.mainListFixture(
            id: 42,
            path: "docs/contracts/customer.pdf",
            category: "docs",
            currentName: "customer.pdf"
        )
        let detailer = MainListRecordingFileDetailer(results: [.success(detail)])
        let model = MainFileListModel(
            opening: .mainListFixture(repoPath: "/tmp/repo", currentCategoryFiles: [detail]),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: detailer,
            errorMapper: MainListRecordingErrorMapper(mapping: .mainListDbFixture(rawContext: "unused"))
        )

        await model.selectFile(id: detail.id)
        let requests = await detailer.recordedRequests()

        XCTAssertEqual(requests, [MainListFileDetailRequest(repoPath: "/tmp/repo", fileID: detail.id)])
        XCTAssertEqual(model.selection, .single(detail.id))
        XCTAssertEqual(model.selectedFileDetail, detail)
        XCTAssertNil(model.detailErrorMapping)
        XCTAssertFalse(model.isDetailLoading)
    }

    @MainActor
    func testMainListMapsMissingSelectedFileDetailInline() async {
        let mapping = CoreErrorMappingSnapshot.mainListFileNotFoundFixture(rawContext: "missing")
        let mapper = MainListRecordingErrorMapper(mapping: mapping)
        let model = MainFileListModel(
            opening: .mainListFixture(repoPath: "/tmp/repo", currentCategoryFiles: []),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: MainListRecordingFileDetailer(results: [
                .failure(CoreError.FileNotFound(path: "docs/missing.pdf")),
            ]),
            errorMapper: mapper
        )

        await model.selectFile(id: 404)
        let mappedErrors = await mapper.recordedErrors()

        XCTAssertNil(model.selectedFileDetail)
        XCTAssertEqual(model.detailErrorMapping, mapping)
        XCTAssertEqual(mappedErrors, [CoreError.FileNotFound(path: "docs/missing.pdf")])
        XCTAssertFalse(model.isDetailLoading)
    }

    @MainActor
    func testMainListClearsDetailWhenCategoryChanges() async {
        let detail = FileEntrySnapshot.mainListFixture(
            id: 8,
            path: "docs/a.pdf",
            category: "docs",
            currentName: "a.pdf"
        )
        let model = MainFileListModel(
            opening: .mainListFixture(repoPath: "/tmp/repo", currentCategoryFiles: [detail]),
            fileLister: MainListRecordingFileLister(results: [.success([])]),
            fileDetailer: MainListRecordingFileDetailer(results: [.success(detail)]),
            errorMapper: MainListRecordingErrorMapper(mapping: .mainListDbFixture(rawContext: "unused"))
        )

        await model.selectFile(id: detail.id)
        await model.loadCurrentCategory("finance")

        XCTAssertEqual(model.selection, .none)
        XCTAssertNil(model.selectedFileDetail)
        XCTAssertNil(model.detailErrorMapping)
        XCTAssertFalse(model.isDetailLoading)
    }

    func testMainListSidebarRowsExposeC115TreeSubdirectoriesForVisibleFiltering() {
        let tree = RepositoryTreeNodeSnapshot.mainListNestedFixtureTree()
        let rows = tree.sidebarRows

        XCTAssertEqual(rows.map(\.id), ["inbox", "docs", "docs/contracts", "docs/references"])
        XCTAssertEqual(rows.map(\.displayName), ["inbox", "docs", "contracts", "references"])
        XCTAssertEqual(rows.map(\.depth), [0, 0, 1, 1])
        XCTAssertEqual(rows.map(\.totalFileCount), [1, 2, 1, 1])
        XCTAssertEqual(tree.sidebarRow(id: "docs/contracts")?.categoryForFileList, "docs")
        XCTAssertEqual(tree.sidebarRow(id: "docs/contracts")?.pathFilterPrefix, "docs/contracts")
    }

    func testMainListTreeSubdirectoryRowFiltersCurrentCategoryFilesWithoutNewCoreCapability() {
        let tree = RepositoryTreeNodeSnapshot.mainListNestedFixtureTree()
        guard let contractsRow = tree.sidebarRow(id: "docs/contracts") else {
            return XCTFail("expected C1-15 contracts tree row")
        }

        let contracts = FileEntrySnapshot.mainListFixture(
            id: 21,
            path: "docs/contracts/customer.pdf",
            category: "docs",
            currentName: "customer.pdf"
        )
        let references = FileEntrySnapshot.mainListFixture(
            id: 22,
            path: "docs/references/research.md",
            category: "docs",
            currentName: "research.md"
        )

        XCTAssertTrue(contractsRow.contains(contracts))
        XCTAssertFalse(contractsRow.contains(references))
        XCTAssertEqual([contracts, references].filter(contractsRow.contains), [contracts])
    }

    func testDefaultCoreBridgeGetsRealFileDetailForMainListSelection() async throws {
        let repoURL = try makeMainListTemporaryRepositoryURL()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let docsURL = repoURL.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)
        try "# User project\n".write(
            to: docsURL.appendingPathComponent("report.md"),
            atomically: true,
            encoding: .utf8
        )

        let bridge = CoreBridge()
        try await bridge.adoptExistingRepository(repoPath: repoURL.path)
        let listed = try await firstListedFile(bridge: bridge, repoPath: repoURL.path, category: "docs")
        let detail = try await bridge.getFile(repoPath: repoURL.path, fileID: listed.id)

        XCTAssertEqual(detail, listed)
        XCTAssertEqual(detail.currentName, listed.currentName)
    }

    func testDefaultCoreBridgeMarksMissingFilesFromFilesystemState() async throws {
        let repoURL = try makeMainListTemporaryRepositoryURL()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let docsURL = repoURL.appendingPathComponent("docs", isDirectory: true)
        let reportURL = docsURL.appendingPathComponent("report.md")
        try FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)
        try "report".write(to: reportURL, atomically: true, encoding: .utf8)

        let bridge = CoreBridge()
        try await bridge.adoptExistingRepository(repoPath: repoURL.path)
        try FileManager.default.removeItem(at: reportURL)
        let listed = try await firstListedFile(bridge: bridge, repoPath: repoURL.path, category: "docs")

        XCTAssertEqual(listed.statusDisplay, "Missing")
    }

    func testDefaultCoreBridgeListsRealPopulatedRepositoryTreeForMainList() async throws {
        let repoURL = try makeMainListTemporaryRepositoryURL()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let contractsURL = repoURL.appendingPathComponent("docs/contracts", isDirectory: true)
        let referencesURL = repoURL.appendingPathComponent("docs/references", isDirectory: true)
        try FileManager.default.createDirectory(at: contractsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: referencesURL, withIntermediateDirectories: true)
        try "contract".write(
            to: contractsURL.appendingPathComponent("customer.pdf"),
            atomically: true,
            encoding: .utf8
        )
        try "research".write(
            to: referencesURL.appendingPathComponent("research.md"),
            atomically: true,
            encoding: .utf8
        )

        let bridge = CoreBridge()
        try await bridge.adoptExistingRepository(repoPath: repoURL.path)
        let tree = try await bridge.listTree(repoPath: repoURL.path, locale: "en")
        let rowIDs = tree.sidebarRows.map(\.id)

        XCTAssertTrue(rowIDs.contains("docs"))
        XCTAssertTrue(rowIDs.contains("docs/contracts"))
        XCTAssertTrue(rowIDs.contains("docs/references"))
        XCTAssertEqual(tree.sidebarRow(id: "docs/contracts")?.categoryForFileList, "docs")
        XCTAssertEqual(tree.sidebarRow(id: "docs/contracts")?.pathFilterPrefix, "docs/contracts")
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

private struct MainListFileDetailRequest: Equatable {
    var repoPath: String
    var fileID: Int64
}

private actor MainListRecordingFileDetailer: CoreFileDetailing {
    enum Result {
        case success(FileEntrySnapshot)
        case failure(Error)
    }

    private var results: [Result]
    private var requests: [MainListFileDetailRequest] = []

    init(results: [Result]) {
        self.results = results
    }

    func getFile(repoPath: String, fileID: Int64) async throws -> FileEntrySnapshot {
        requests.append(MainListFileDetailRequest(repoPath: repoPath, fileID: fileID))
        guard !results.isEmpty else {
            throw CoreError.FileNotFound(path: "\(fileID)")
        }

        switch results.removeFirst() {
        case .success(let file):
            return file
        case .failure(let error):
            throw error
        }
    }

    func recordedRequests() -> [MainListFileDetailRequest] { requests }
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

    static func mainListNestedFixtureTree() -> RepositoryTreeNodeSnapshot {
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
                    fileCount: 0,
                    children: [
                        RepositoryTreeNodeSnapshot(
                            slug: "contracts",
                            displayName: "contracts",
                            kind: "Subdir",
                            relativePath: "docs/contracts",
                            fileCount: 1,
                            depth: 2,
                            children: []
                        ),
                        RepositoryTreeNodeSnapshot(
                            slug: "references",
                            displayName: "references",
                            kind: "Subdir",
                            relativePath: "docs/references",
                            fileCount: 1,
                            depth: 2,
                            children: []
                        ),
                    ]
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

    static func mainListFileNotFoundFixture(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .fileNotFound,
            userMessage: "文件不存在",
            severity: .medium,
            suggestedAction: "刷新当前列表，确认文件是否已被移动或删除。",
            recoverability: .refreshRequired,
            rawContext: rawContext
        )
    }
}

private func makeMainListTemporaryRepositoryURL() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixMainListTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func firstListedFile(
    bridge: CoreBridge,
    repoPath: String,
    category: String
) async throws -> FileEntrySnapshot {
    let files = try await bridge.listFiles(repoPath: repoPath, filter: .currentCategory(category))
    if let first = files.first {
        return first
    }

    throw CoreError.FileNotFound(path: "\(repoPath)#\(category)")
}
