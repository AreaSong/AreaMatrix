import Foundation

protocol CoreEmptyRepositoryOpening: Sendable {
    func openEmptyRepository(repoPath: String) async throws -> RepositoryOpeningResult
    func openAdoptedRepository(repoPath: String) async throws -> RepositoryOpeningResult
}

extension CoreEmptyRepositoryOpening {
    func openConfiguredRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        try await openAdoptedRepository(repoPath: repoPath)
    }
}

struct RepositoryOpeningResult: Equatable, Sendable {
    var config: RepoConfigSnapshot
    var tree: RepositoryTreeNodeSnapshot
    var currentCategoryFiles: [FileEntrySnapshot]

    var isEmpty: Bool {
        tree.totalFileCount == 0
    }
}

struct RepositoryTreeNodeSnapshot: Equatable, Identifiable, Sendable {
    var slug: String
    var displayName: String
    var fileCount: Int64
    var children: [RepositoryTreeNodeSnapshot]

    var id: String {
        slug.isEmpty ? displayName : slug
    }

    var totalFileCount: Int64 {
        max(fileCount, children.reduce(0) { $0 + $1.totalFileCount })
    }
}

extension CoreBridge: CoreEmptyRepositoryOpening {
    func openEmptyRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        try await openInitializedRepository(repoPath: repoPath, loadsCurrentCategoryFiles: true)
    }

    func openAdoptedRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        try await openInitializedRepository(repoPath: repoPath, loadsCurrentCategoryFiles: false)
    }

    private func openInitializedRepository(
        repoPath: String,
        loadsCurrentCategoryFiles: Bool
    ) async throws -> RepositoryOpeningResult {
        let config = RepoConfigSnapshot(coreConfig: try loadOpeningCoreConfig(repoPath: repoPath))
        let treeJSON = try listOpeningCoreTreeJSON(repoPath: repoPath, locale: config.locale)
        let tree = try decodeOpeningTreeSnapshot(treeJSON)
        let files = try currentCategoryFiles(
            repoPath: repoPath,
            tree: tree,
            shouldLoad: loadsCurrentCategoryFiles
        )
        return RepositoryOpeningResult(
            config: config,
            tree: tree,
            currentCategoryFiles: files
        )
    }
}

private func loadOpeningCoreConfig(repoPath: String) throws -> RepoConfig {
    try loadConfig(repoPath: repoPath)
}

private func listOpeningCoreTreeJSON(repoPath: String, locale: String) throws -> String {
    try listTreeJson(repoPath: repoPath, locale: locale)
}

private func listOpeningCoreFiles(repoPath: String, filter: FileFilterSnapshot) throws -> [FileEntry] {
    try listFiles(repoPath: repoPath, filter: FileFilter(filter))
}

private func currentCategoryFiles(
    repoPath: String,
    tree: RepositoryTreeNodeSnapshot,
    shouldLoad: Bool
) throws -> [FileEntrySnapshot] {
    guard shouldLoad else { return [] }

    return try listOpeningCoreFiles(
        repoPath: repoPath,
        filter: FileFilterSnapshot.currentCategory(tree.defaultCategory)
    ).map(FileEntrySnapshot.init(coreEntry:))
}

private func decodeOpeningTreeSnapshot(_ json: String) throws -> RepositoryTreeNodeSnapshot {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let decoded = try decoder.decode(DecodedRepositoryTreeNode.self, from: Data(json.utf8))
    return RepositoryTreeNodeSnapshot(decoded)
}

private struct DecodedRepositoryTreeNode: Decodable {
    var slug: String
    var displayName: String
    var fileCount: Int64
    var children: [DecodedRepositoryTreeNode]

    private enum CodingKeys: String, CodingKey {
        case slug
        case displayName
        case fileCount
        case children
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        slug = try container.decode(String.self, forKey: .slug)
        displayName = try container.decode(String.self, forKey: .displayName)
        fileCount = try container.decode(Int64.self, forKey: .fileCount)
        children = try container.decodeIfPresent([DecodedRepositoryTreeNode].self, forKey: .children) ?? []
    }
}

private extension RepositoryTreeNodeSnapshot {
    init(_ decoded: DecodedRepositoryTreeNode) {
        slug = decoded.slug
        displayName = decoded.displayName
        fileCount = decoded.fileCount
        children = decoded.children.map(RepositoryTreeNodeSnapshot.init)
    }

    var defaultCategory: String? {
        let firstNode = children.first ?? self
        return firstNode.slug == "__root__" ? nil : firstNode.slug
    }
}
