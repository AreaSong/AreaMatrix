@testable import AreaMatrix
import XCTest

final class MainListFilesTests: XCTestCase {
    @MainActor
    func testMainListLoadsSelectedCategoryThroughListFilesCoreListFiles() async {
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
            fileDetailer: RecordingFileDetailer(results: []),
            errorMapper: StaticCoreErrorMapper(mapping: .mainListDbFixture(rawContext: "unused"))
        )

        await model.loadCurrentCategory("docs")

        await lister.assertFileListRequests([
            FileListRequest(repoPath: "/tmp/repo", filter: .currentCategory("docs"))
        ])
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
        let lister = MainListRecordingFileLister(results: [
            .failure(CoreError.Db(message: "locked")),
            .success([docsFile])
        ])
        let mapper = StaticCoreErrorMapper(mapping: .mainListDbFixture(rawContext: "locked"))
        let model = MainFileListModel(
            opening: .mainListFixture(repoPath: "/tmp/repo", currentCategoryFiles: []),
            fileLister: lister,
            fileDetailer: RecordingFileDetailer(results: []),
            errorMapper: mapper
        )

        await model.loadCurrentCategory("docs")
        await model.retryCurrentCategory()

        await lister.assertFileListRequests([
            FileListRequest(repoPath: "/tmp/repo", filter: .currentCategory("docs")),
            FileListRequest(repoPath: "/tmp/repo", filter: .currentCategory("docs"))
        ])
        XCTAssertEqual(model.files, [docsFile])
        XCTAssertNil(model.errorMapping)
    }

    @MainActor
    func testMainListKeepsListFailureInline() async {
        let mapping = CoreErrorMappingSnapshot.mainListDbFixture(rawContext: "list db locked")
        let mapper = StaticCoreErrorMapper(mapping: mapping)
        let model = MainFileListModel(
            opening: .mainListFixture(
                repoPath: "/tmp/repo",
                currentCategoryFiles: [.mainListFixture(
                    id: 1,
                    path: "inbox/a.txt",
                    category: "inbox",
                    currentName: "a.txt"
                )]
            ),
            fileLister: MainListRecordingFileLister(results: [.failure(CoreError.Db(message: "list db locked"))]),
            fileDetailer: RecordingFileDetailer(results: []),
            errorMapper: mapper
        )

        await model.loadCurrentCategory("docs")

        XCTAssertEqual(model.files, [])
        XCTAssertEqual(model.errorMapping, mapping)
        await mapper.assertMappedCoreErrors([CoreError.Db(message: "list db locked")])
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testMainListLoadsSelectedFileDetailThroughGetFileDetailCoreGetFile() async {
        let detail = FileEntrySnapshot.mainListFixture(
            id: 42,
            path: "docs/contracts/customer.pdf",
            category: "docs",
            currentName: "customer.pdf"
        )
        let detailer = RecordingFileDetailer(results: [.success(detail)])
        let model = MainFileListModel(
            opening: .mainListFixture(repoPath: "/tmp/repo", currentCategoryFiles: [detail]),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: detailer,
            errorMapper: StaticCoreErrorMapper(mapping: .mainListDbFixture(rawContext: "unused"))
        )

        await model.selectFile(id: detail.id)

        await detailer.assertFileDetailRequests([
            FileDetailRequest(repoPath: "/tmp/repo", fileID: detail.id)
        ])
        XCTAssertEqual(model.selection, .single(detail.id))
        XCTAssertEqual(model.selectedFileDetail, detail)
        XCTAssertNil(model.detailErrorMapping)
        XCTAssertFalse(model.isDetailLoading)
    }

    @MainActor
    func testMainListMapsMissingSelectedFileDetailInline() async {
        let cached = FileEntrySnapshot.mainListFixture(
            id: 404,
            path: "docs/missing.pdf",
            category: "docs",
            currentName: "missing.pdf"
        )
        let mapping = CoreErrorMappingSnapshot.mainListFileNotFoundFixture(rawContext: "missing")
        let mapper = StaticCoreErrorMapper(mapping: mapping)
        let model = MainFileListModel(
            opening: .mainListFixture(repoPath: "/tmp/repo", currentCategoryFiles: [cached]),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: RecordingFileDetailer(results: [
                .failure(CoreError.FileNotFound(path: "docs/missing.pdf"))
            ]),
            errorMapper: mapper
        )

        await model.selectFile(id: 404)

        var missingCached = cached
        missingCached.availability = .missing
        XCTAssertEqual(model.selectedFileDetail, missingCached)
        XCTAssertEqual(model.detailErrorMapping, mapping)
        await mapper.assertMappedCoreErrors([CoreError.FileNotFound(path: "docs/missing.pdf")])
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
            fileDetailer: RecordingFileDetailer(results: [.success(detail)]),
            errorMapper: StaticCoreErrorMapper(mapping: .mainListDbFixture(rawContext: "unused"))
        )

        await model.selectFile(id: detail.id)
        await model.loadCurrentCategory("finance")

        XCTAssertEqual(model.selection, .none)
        XCTAssertNil(model.selectedFileDetail)
        XCTAssertNil(model.detailErrorMapping)
        XCTAssertFalse(model.isDetailLoading)
    }

    func testMainListSidebarRowsExposeBuildTreeCoreTreeSubdirectoriesForVisibleFiltering() {
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
            return XCTFail("expected build-tree contracts tree row")
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
        defer { removeTestTemporaryItems(repoURL) }
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
        defer { removeTestTemporaryItems(repoURL) }
        let docsURL = repoURL.appendingPathComponent("docs", isDirectory: true)
        let reportURL = docsURL.appendingPathComponent("report.md")
        try FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)
        try "report".write(to: reportURL, atomically: true, encoding: .utf8)

        let bridge = CoreBridge()
        try await bridge.adoptExistingRepository(repoPath: repoURL.path)
        try removeTestTemporaryItem(reportURL)
        let listed = try await firstListedFile(bridge: bridge, repoPath: repoURL.path, category: "docs")

        XCTAssertEqual(listed.statusDisplay, "Missing")
    }

    func testDefaultCoreBridgeListsRealPopulatedRepositoryTreeForMainList() async throws {
        let repoURL = try makeMainListTemporaryRepositoryURL()
        defer { removeTestTemporaryItems(repoURL) }
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

private func makeMainListTemporaryRepositoryURL() throws -> URL {
    try makeTestTemporaryDirectory(named: "AreaMatrixMainListTests")
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
