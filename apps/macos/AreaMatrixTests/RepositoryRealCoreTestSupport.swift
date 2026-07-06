@testable import AreaMatrix
import Foundation

struct RealCoreRepositoryTestContext {
    let repoURL: URL
    let sourceRootURL: URL
    let bridge: CoreBridge

    func cleanUp() {
        removeTestTemporaryItems(repoURL, sourceRootURL)
    }

    func sourceFileURL(named fileName: String) -> URL {
        sourceRootURL.appendingPathComponent(fileName)
    }

    func repositoryFileURL(for entry: FileEntrySnapshot) -> URL {
        repoURL.appendingPathComponent(entry.path)
    }

    @discardableResult
    func writeSourceFile(named fileName: String, contents: String) throws -> URL {
        let url = sourceFileURL(named: fileName)
        try Data(contents.utf8).write(to: url)
        return url
    }
}

func makeRealCoreRepositoryTestContext(
    named name: String,
    repoPrefix: String = "repo",
    sourcePrefix: String = "source"
) async throws -> RealCoreRepositoryTestContext {
    let repoURL = try makeTestTemporaryDirectory(prefix: repoPrefix, named: name)
    let sourceRootURL = try makeTestTemporaryDirectory(prefix: sourcePrefix, named: name)
    let bridge = CoreBridge()

    do {
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        return RealCoreRepositoryTestContext(
            repoURL: repoURL,
            sourceRootURL: sourceRootURL,
            bridge: bridge
        )
    } catch {
        removeTestTemporaryItems(repoURL, sourceRootURL)
        throw error
    }
}

func makeRealCoreRepositoryOpening(
    _ context: RealCoreRepositoryTestContext,
    currentCategory: String? = nil
) async throws -> RepositoryOpeningResult {
    let config = try await context.bridge.loadConfig(repoPath: context.repoURL.path)
    let tree = try await context.bridge.listTree(repoPath: context.repoURL.path, locale: "zh-Hans")
    let files: [FileEntrySnapshot] = if let currentCategory {
        try await context.bridge.listFiles(
            repoPath: context.repoURL.path,
            filter: .currentCategory(currentCategory)
        )
    } else {
        []
    }

    return RepositoryOpeningResult(config: config, tree: tree, currentCategoryFiles: files)
}
