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

enum FileActionsCoreCall: Equatable {
    case rename(fileID: Int64, newName: String)
    case previewMove(fileID: Int64, targetCategory: String)
    case move(fileID: Int64, targetCategory: String)
    case removeIndex(fileID: Int64)
    case delete(fileID: Int64)

    var isDeclaredFileActionCapability: Bool {
        switch self {
        case .rename, .delete, .removeIndex, .previewMove, .move:
            true
        }
    }
}

actor FileActionsRecordingCore: CoreFileListing,
    CoreFileDetailing,
    CoreFileRenaming,
    CoreFileDeleting,
    CoreFileCategoryMoving,
    CoreChangeLogListing,
    CoreErrorMapping {
    private var filesByID: [Int64: FileEntrySnapshot]
    private var calls: [FileActionsCoreCall] = []

    init(files: [FileEntrySnapshot]) {
        filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
    }

    func listFiles(repoPath _: String, filter: FileFilterSnapshot) async throws -> [FileEntrySnapshot] {
        filesByID.values
            .filter { filter.category == nil || $0.category == filter.category }
            .sorted { $0.id < $1.id }
    }

    func getFile(repoPath _: String, fileID: Int64) async throws -> FileEntrySnapshot {
        guard let file = filesByID[fileID] else {
            throw CoreError.FileNotFound(path: "\(fileID)")
        }
        return file
    }

    func renameFile(repoPath: String, fileID: Int64, newName: String) async throws -> FileEntrySnapshot {
        calls.append(.rename(fileID: fileID, newName: newName))
        var file = try await getFile(repoPath: repoPath, fileID: fileID)
        file.currentName = newName
        file.path = "\(file.path.split(separator: "/").dropLast().joined(separator: "/"))/\(newName)"
        filesByID[fileID] = file
        return file
    }

    func deleteFile(repoPath _: String, fileID: Int64) async throws {
        calls.append(.delete(fileID: fileID))
        filesByID.removeValue(forKey: fileID)
    }

    func removeIndexEntry(repoPath _: String, fileID: Int64) async throws {
        calls.append(.removeIndex(fileID: fileID))
        filesByID.removeValue(forKey: fileID)
    }

    func previewMoveToCategory(
        repoPath: String,
        fileID: Int64,
        newCategory: String
    ) async throws -> MoveToCategoryPreviewSnapshot {
        calls.append(.previewMove(fileID: fileID, targetCategory: newCategory))
        let file = try await getFile(repoPath: repoPath, fileID: fileID)
        return MoveToCategoryPreviewSnapshot(
            fileID: file.id,
            fromCategory: file.category,
            toCategory: newCategory,
            currentPath: file.path,
            targetPath: "\(newCategory)/\(file.currentName)",
            targetName: file.currentName,
            storageMode: file.storageMode,
            indexOnly: file.storageMode == "Indexed",
            nameConflictResolved: false,
            willMoveFile: file.storageMode != "Indexed"
        )
    }

    func moveToCategory(repoPath: String, fileID: Int64, newCategory: String) async throws -> FileEntrySnapshot {
        calls.append(.move(fileID: fileID, targetCategory: newCategory))
        var file = try await getFile(repoPath: repoPath, fileID: fileID)
        file.category = newCategory
        file.path = "\(newCategory)/\(file.currentName)"
        filesByID[fileID] = file
        return file
    }

    func listChanges(repoPath _: String, filter _: ChangeFilterSnapshot) async throws -> [ChangeLogEntrySnapshot] {
        []
    }

    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .internal,
            userMessage: "\(error)",
            severity: .high,
            suggestedAction: "Retry the file action.",
            recoverability: .retryable,
            rawContext: "file-actions integration verify"
        )
    }

    func recordedActionCalls() -> [FileActionsCoreCall] {
        calls
    }
}

extension RepositoryOpeningResult {
    static func fileActionsFixture(repoPath: String, files: [FileEntrySnapshot]) -> RepositoryOpeningResult {
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
            tree: .fileActionsTree(docsCount: Int64(files.count), financeCount: 0),
            currentCategoryFiles: files
        )
    }
}

extension RepositoryTreeNodeSnapshot {
    static func fileActionsTree(docsCount: Int64, financeCount: Int64) -> RepositoryTreeNodeSnapshot {
        RepositoryTreeNodeSnapshot(
            slug: "__root__",
            displayName: "Repository",
            kind: "RepositoryRoot",
            relativePath: "",
            fileCount: 0,
            depth: 0,
            children: [
                RepositoryTreeNodeSnapshot(slug: "docs", displayName: "docs", fileCount: docsCount, children: []),
                RepositoryTreeNodeSnapshot(
                    slug: "finance",
                    displayName: "finance",
                    fileCount: financeCount,
                    children: []
                )
            ]
        )
    }
}

extension FileEntrySnapshot {
    static func fileActionsFixture(id: Int64, name: String, storageMode: String) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: "docs/\(name)",
            originalName: name,
            currentName: name,
            category: "docs",
            sizeBytes: 128,
            hashSha256: "file-actions-\(id)",
            storageMode: storageMode,
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000,
            updatedAt: 1_700_000_100
        )
    }
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

func makeFileActionsTemporaryDirectory(prefix: String) throws -> URL {
    try makeTestTemporaryDirectory(prefix: prefix, named: "AreaMatrixFileActions")
}
