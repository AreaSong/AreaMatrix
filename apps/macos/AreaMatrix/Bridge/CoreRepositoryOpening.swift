import Foundation

protocol CoreEmptyRepositoryOpening: Sendable {
    func openEmptyRepository(repoPath: String) async throws -> RepositoryOpeningResult
    func openAdoptedRepository(repoPath: String) async throws -> RepositoryOpeningResult
}

protocol CoreRepositoryTreeListing: Sendable {
    func listTree(repoPath: String, locale: String) async throws -> RepositoryTreeNodeSnapshot
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
    var kind: String
    var relativePath: String
    var fileCount: Int64
    var sizeBytes: Int64
    var depth: Int64
    var children: [RepositoryTreeNodeSnapshot]

    init(
        slug: String,
        displayName: String,
        kind: String = "SystemCategory",
        relativePath: String? = nil,
        fileCount: Int64,
        sizeBytes: Int64 = 0,
        depth: Int64 = 1,
        children: [RepositoryTreeNodeSnapshot]
    ) {
        self.slug = slug
        self.displayName = displayName
        self.kind = kind
        self.relativePath = relativePath ?? (slug == "__root__" ? "" : slug)
        self.fileCount = fileCount
        self.sizeBytes = sizeBytes
        self.depth = depth
        self.children = children
    }

    var id: String {
        relativePath.isEmpty ? slug : relativePath
    }

    var totalFileCount: Int64 {
        max(fileCount, children.reduce(0) { $0 + $1.totalFileCount })
    }

    var sidebarNodes: [RepositoryTreeNodeSnapshot] {
        let nodes = children.isEmpty ? [self] : children
        return Self.sortForSidebar(nodes)
    }

    private static func sortForSidebar(
        _ nodes: [RepositoryTreeNodeSnapshot]
    ) -> [RepositoryTreeNodeSnapshot] {
        nodes.enumerated().sorted { lhs, rhs in
            let leftOrder = sidebarCategoryOrder[lhs.element.slug]
            let rightOrder = sidebarCategoryOrder[rhs.element.slug]

            switch (leftOrder, rightOrder) {
            case let (left?, right?):
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    private static let sidebarCategoryOrder = [
        "inbox": 0,
        "docs": 1,
        "code": 2,
        "design": 3,
        "finance": 4,
        "media": 5,
    ]
}

extension CoreBridge: CoreEmptyRepositoryOpening, CoreRepositoryTreeListing {
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
        let tree = try await listTree(repoPath: repoPath, locale: config.locale)
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

    func listTree(repoPath: String, locale: String) async throws -> RepositoryTreeNodeSnapshot {
        let treeJSON = try await listTreeJSON(repoPath: repoPath, locale: locale)
        return try decodeOpeningTreeSnapshot(treeJSON)
    }
}

private func loadOpeningCoreConfig(repoPath: String) throws -> RepoConfig {
    try loadConfig(repoPath: repoPath)
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
    var kind: String
    var relativePath: String
    var fileCount: Int64
    var sizeBytes: Int64
    var depth: Int64
    var children: [DecodedRepositoryTreeNode]

    private enum CodingKeys: String, CodingKey {
        case slug
        case displayName
        case kind
        case relativePath
        case fileCount
        case sizeBytes
        case depth
        case children
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        slug = try container.decode(String.self, forKey: .slug)
        displayName = try container.decode(String.self, forKey: .displayName)
        kind = try container.decode(String.self, forKey: .kind)
        relativePath = try container.decode(String.self, forKey: .relativePath)
        fileCount = try container.decode(Int64.self, forKey: .fileCount)
        sizeBytes = try container.decode(Int64.self, forKey: .sizeBytes)
        depth = try container.decode(Int64.self, forKey: .depth)
        children = try container.decodeIfPresent([DecodedRepositoryTreeNode].self, forKey: .children) ?? []
    }
}

private extension RepositoryTreeNodeSnapshot {
    init(_ decoded: DecodedRepositoryTreeNode) {
        self.init(
            slug: decoded.slug,
            displayName: decoded.displayName,
            kind: decoded.kind,
            relativePath: decoded.relativePath,
            fileCount: decoded.fileCount,
            sizeBytes: decoded.sizeBytes,
            depth: decoded.depth,
            children: decoded.children.map(RepositoryTreeNodeSnapshot.init)
        )
    }

    var defaultCategory: String? {
        let firstNode = children.first ?? self
        return firstNode.slug == "__root__" ? nil : firstNode.slug
    }
}
