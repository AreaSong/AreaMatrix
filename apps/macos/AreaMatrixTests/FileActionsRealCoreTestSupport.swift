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

@MainActor
func makeFileActionsRealCoreContext() async throws -> FileActionsRealCoreContext {
    let context = try await makeRealCoreRepositoryTestContext(named: "AreaMatrixFileActions")
    let ownedSourceURL = try context.writeSourceFile(named: "contract.pdf", contents: "owned bytes")
    let indexedSourceURL = try context.writeSourceFile(named: "external.pdf", contents: "indexed bytes")
    let indexedSourceBefore = try Data(contentsOf: indexedSourceURL)

    let owned = try await context.bridge.importCopiedFile(
        repoPath: context.repoURL.path,
        sourceURL: ownedSourceURL,
        overrideCategory: "docs",
        overrideFilename: "contract.pdf",
        duplicateStrategy: .skip
    )
    let indexed = try await context.bridge.importIndexedFile(
        repoPath: context.repoURL.path,
        sourceURL: indexedSourceURL,
        overrideCategory: "docs",
        overrideFilename: "external.pdf",
        duplicateStrategy: .skip
    )

    let opening = try await makeRealCoreRepositoryOpening(context, currentCategory: "docs")
    let model = MainFileListModel(
        opening: opening,
        fileLister: context.bridge,
        fileDetailer: context.bridge,
        fileRenamer: context.bridge,
        fileDeleter: context.bridge,
        fileCategoryMover: context.bridge,
        changeLogLister: context.bridge,
        errorMapper: context.bridge
    )

    return FileActionsRealCoreContext(
        repoURL: context.repoURL,
        sourceRootURL: context.sourceRootURL,
        indexedSourceURL: indexedSourceURL,
        indexedSourceBefore: indexedSourceBefore,
        bridge: context.bridge,
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
