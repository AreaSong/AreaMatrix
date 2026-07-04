@testable import AreaMatrix
import Foundation
import XCTest

struct FileActionsRealCoreContext {
    var repoURL: URL
    var sourceRootURL: URL
    var indexedSourceURL: URL
    var indexedSourceBefore: Data
    var bridge: CoreBridge
    var opening: RepositoryOpeningResult
    var model: MainFileListModel
    var ownedFile: FileEntrySnapshot
    var indexedFile: FileEntrySnapshot

    func cleanUp() {
        removeTestTemporaryItems(repoURL, sourceRootURL)
    }
}

func makeFileActionsTemporaryDirectory(prefix: String) throws -> URL {
    try makeTestTemporaryDirectory(prefix: prefix, named: "AreaMatrixFileActions")
}

func makeFileActionsOpening(
    repoURL: URL,
    bridge: CoreBridge,
    category: String
) async throws -> RepositoryOpeningResult {
    let config = try await bridge.loadConfig(repoPath: repoURL.path)
    let tree = try await bridge.listTree(repoPath: repoURL.path, locale: "zh-Hans")
    let files = try await bridge.listFiles(repoPath: repoURL.path, filter: .currentCategory(category))
    return RepositoryOpeningResult(config: config, tree: tree, currentCategoryFiles: files)
}

@MainActor
func makeFileActionsRealCoreContext() async throws -> FileActionsRealCoreContext {
    let repoURL = try makeFileActionsTemporaryDirectory(prefix: "repo")
    let sourceRootURL = try makeFileActionsTemporaryDirectory(prefix: "source")
    let ownedSourceURL = sourceRootURL.appendingPathComponent("contract.pdf")
    let indexedSourceURL = sourceRootURL.appendingPathComponent("external.pdf")
    try Data("owned bytes".utf8).write(to: ownedSourceURL)
    try Data("indexed bytes".utf8).write(to: indexedSourceURL)
    let indexedSourceBefore = try Data(contentsOf: indexedSourceURL)

    let bridge = CoreBridge()
    try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
    let owned = try await bridge.importCopiedFile(
        repoPath: repoURL.path,
        sourceURL: ownedSourceURL,
        overrideCategory: "docs",
        overrideFilename: "contract.pdf",
        duplicateStrategy: .skip
    )
    let indexed = try await bridge.importIndexedFile(
        repoPath: repoURL.path,
        sourceURL: indexedSourceURL,
        overrideCategory: "docs",
        overrideFilename: "external.pdf",
        duplicateStrategy: .skip
    )

    let opening = try await makeFileActionsOpening(repoURL: repoURL, bridge: bridge, category: "docs")
    let model = MainFileListModel(
        opening: opening,
        fileLister: bridge,
        fileDetailer: bridge,
        fileRenamer: bridge,
        fileDeleter: bridge,
        fileCategoryMover: bridge,
        changeLogLister: bridge,
        errorMapper: bridge
    )

    return FileActionsRealCoreContext(
        repoURL: repoURL,
        sourceRootURL: sourceRootURL,
        indexedSourceURL: indexedSourceURL,
        indexedSourceBefore: indexedSourceBefore,
        bridge: bridge,
        opening: opening,
        model: model,
        ownedFile: owned,
        indexedFile: indexed
    )
}

func assertChangeLogContains(
    _ action: String,
    fileID: Int64,
    repoURL: URL,
    bridge: CoreBridge
) async throws {
    let changes = try await bridge.listChanges(repoPath: repoURL.path, filter: .detailLog(fileID: fileID))
    XCTAssertTrue(changes.contains { $0.action == action })
}
