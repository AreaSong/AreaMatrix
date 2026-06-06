@testable import AreaMatrixIOS
import Foundation
import XCTest

@MainActor
final class MobileLibraryModelTests: XCTestCase {
    func testLoadQueriesCoreTreeAndPagedFiles() async {
        let bridge = FakeMobileLibraryCoreBridge(
            tree: .fixture(children: [.category(slug: "docs", name: "Documents", count: 2)]),
            files: [
                .fixture(id: 1, name: "old.pdf", updatedAt: 10),
                .fixture(id: 2, name: "missing.pdf", availability: .missing, updatedAt: 20)
            ]
        )
        let model = LibraryListViewModel(connection: connection(path: "/tmp/Repo"), bridge: bridge)

        await model.loadIfNeeded()

        let fileRequests = await bridge.fileRequestSnapshot()
        let treeRequests = await bridge.treeRequestSnapshot()
        XCTAssertEqual(fileRequests.map(\.filter), [.page(category: nil)])
        XCTAssertEqual(treeRequests.map(\.locale), ["zh-Hans"])
        XCTAssertEqual(model.categories.map(\.displayName), ["Documents"])
        XCTAssertEqual(model.files.map(\.currentName), ["missing.pdf", "old.pdf"])
        XCTAssertEqual(model.needsReview.map(\.currentName), ["missing.pdf"])
        XCTAssertEqual(model.statusText, "Synced just now")
    }

    func testSelectingCategoryReloadsFilesWithCoreFilter() async {
        let category = MobileLibraryTreeNode.category(slug: "docs", name: "Documents", count: 1)
        let bridge = FakeMobileLibraryCoreBridge(
            tree: .fixture(children: [category]),
            files: [.fixture(id: 1, name: "all.pdf", category: "inbox")],
            categoryFiles: ["docs": [.fixture(id: 2, name: "doc.pdf", category: "docs")]]
        )
        let model = LibraryListViewModel(connection: connection(path: "/tmp/Repo"), bridge: bridge)

        await model.loadIfNeeded()
        guard let docs = model.categories.first else {
            return XCTFail("expected category from Core tree")
        }
        await model.selectCategory(docs)

        let fileRequests = await bridge.fileRequestSnapshot()
        XCTAssertEqual(fileRequests.map(\.filter.category), [nil, "docs"])
        XCTAssertEqual(model.selectedCategory?.displayName, "Documents")
        XCTAssertEqual(model.files.map(\.currentName), ["doc.pdf"])
    }

    func testReloadFailureKeepsCachedFilesAndMapsError() async {
        let bridge = FakeMobileLibraryCoreBridge(
            tree: .fixture(children: []),
            files: [.fixture(id: 1, name: "cached.pdf")]
        )
        let model = LibraryListViewModel(connection: connection(path: "/tmp/Repo"), bridge: bridge)

        await model.loadIfNeeded()
        await bridge.setFileError(.database("metadata locked"))
        await model.refresh()

        XCTAssertEqual(model.files.map(\.currentName), ["cached.pdf"])
        XCTAssertEqual(model.error, .database("metadata locked"))
        XCTAssertEqual(model.statusText, "metadata locked")
    }

    func testLiveBridgeLoadsEmptyMobileLibraryThroughCore() async throws {
        let url = try makeTemporaryRepositoryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let bridge = LiveMobileRepositoryCoreBridge()

        try await bridge.initializeEmptyRepository(repoPath: url.path)
        let tree = try await bridge.listTree(repoPath: url.path, locale: "zh-Hans")
        let files = try await bridge.listFiles(repoPath: url.path, filter: .page(category: nil))

        XCTAssertEqual(tree.totalFileCount, 0)
        XCTAssertTrue(files.isEmpty)
    }

    private func connection(path: String) -> MobileRepositoryConnection {
        MobileRepositoryConnection(
            validation: .initialized(path: path),
            config: MobileRepositoryConfig(repoPath: path, defaultMode: "Copied", locale: "zh-Hans"),
            bookmark: RepositoryBookmark(
                url: URL(fileURLWithPath: path),
                displayName: "Repository",
                pathDisplay: path,
                lastOpenedAt: Date(timeIntervalSince1970: 0)
            )
        )
    }
}

actor FakeMobileLibraryCoreBridge: MobileLibraryCoreBridge {
    typealias FileRequest = (repoPath: String, filter: MobileLibraryFileFilter)
    typealias TreeRequest = (repoPath: String, locale: String)

    private let tree: MobileLibraryTreeNode
    private let files: [MobileLibraryFile]
    private let categoryFiles: [String: [MobileLibraryFile]]
    private var fileError: MobileLibraryQueryError?
    private var fileRequests: [FileRequest] = []
    private var treeRequests: [TreeRequest] = []

    init(
        tree: MobileLibraryTreeNode,
        files: [MobileLibraryFile],
        categoryFiles: [String: [MobileLibraryFile]] = [:]
    ) {
        self.tree = tree
        self.files = files
        self.categoryFiles = categoryFiles
    }

    func listFiles(repoPath: String, filter: MobileLibraryFileFilter) async throws -> [MobileLibraryFile] {
        fileRequests.append((repoPath, filter))
        if let fileError {
            throw fileError
        }
        if let category = filter.category, let categoryResult = categoryFiles[category] {
            return categoryResult
        }
        return files
    }

    func listTree(repoPath: String, locale: String) async throws -> MobileLibraryTreeNode {
        treeRequests.append((repoPath, locale))
        return tree
    }

    func setFileError(_ error: MobileLibraryQueryError?) {
        fileError = error
    }

    func fileRequestSnapshot() -> [FileRequest] {
        fileRequests
    }

    func treeRequestSnapshot() -> [TreeRequest] {
        treeRequests
    }
}

private extension MobileLibraryTreeNode {
    static func fixture(children: [MobileLibraryTreeNode]) -> MobileLibraryTreeNode {
        MobileLibraryTreeNode(
            slug: "__root__",
            displayName: "Repository",
            kind: "RepositoryRoot",
            relativePath: "",
            fileCount: 0,
            sizeBytes: 0,
            depth: 0,
            children: children
        )
    }

    static func category(slug: String, name: String, count: Int64) -> MobileLibraryTreeNode {
        MobileLibraryTreeNode(
            slug: slug,
            displayName: name,
            kind: "SystemCategory",
            relativePath: slug,
            fileCount: count,
            sizeBytes: 0,
            depth: 1,
            children: []
        )
    }
}

private extension MobileLibraryFile {
    static func fixture(
        id: Int64,
        name: String,
        category: String = "docs",
        availability: MobileLibraryFileAvailability = .available,
        updatedAt: Int64 = 10
    ) -> MobileLibraryFile {
        MobileLibraryFile(
            id: id,
            path: "\(category)/\(name)",
            originalName: name,
            currentName: name,
            category: category,
            sizeBytes: 42,
            hashSha256: "hash-\(id)",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            availability: availability,
            importedAt: 1,
            updatedAt: updatedAt
        )
    }
}
