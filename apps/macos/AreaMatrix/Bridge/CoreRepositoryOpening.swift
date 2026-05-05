import Foundation

protocol CoreEmptyRepositoryOpening: Sendable {
    func openConfiguredRepository(repoPath: String) async throws -> RepositoryOpeningResult
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
    var currentCategoryListError: CoreErrorMappingSnapshot? = nil
    var isReadOnly: Bool = false
    var writeLockedFileIDs: Set<Int64> = []

    var isEmpty: Bool {
        tree.totalFileCount == 0 && currentCategoryFiles.isEmpty
    }
}

struct RepositoryCurrentCategoryFilesResult: Equatable, Sendable {
    var files: [FileEntrySnapshot]
    var errorMapping: CoreErrorMappingSnapshot?
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

    var sidebarRows: [RepositorySidebarRowSnapshot] {
        let nodes = children.isEmpty ? [self] : children
        return Self.sortForSidebar(nodes).flatMap { $0.sidebarRows(depth: 0) }
    }

    func sidebarRow(id: String) -> RepositorySidebarRowSnapshot? {
        sidebarRows.first { $0.id == id }
    }

    private func sidebarRows(depth: Int) -> [RepositorySidebarRowSnapshot] {
        let childRows = Self.sortForSidebar(children).flatMap { $0.sidebarRows(depth: depth + 1) }
        return [RepositorySidebarRowSnapshot(node: self, depth: depth)] + childRows
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

struct RepositorySidebarRowSnapshot: Equatable, Identifiable, Sendable {
    var node: RepositoryTreeNodeSnapshot
    var depth: Int

    var id: String { node.id }
    var displayName: String { node.displayName }
    var totalFileCount: Int64 { node.totalFileCount }

    var categoryForFileList: String? {
        let path = node.relativePath
        guard !path.isEmpty else {
            return node.slug == "__root__" ? nil : node.slug
        }

        return path.split(separator: "/").first.map(String.init)
    }

    var pathFilterPrefix: String? {
        let path = node.relativePath
        guard path.contains("/") else { return nil }
        return path
    }

    func contains(_ file: FileEntrySnapshot) -> Bool {
        guard let pathFilterPrefix else { return true }
        return file.path == pathFilterPrefix || file.path.hasPrefix("\(pathFilterPrefix)/")
    }
}

extension CoreBridge: CoreEmptyRepositoryOpening, CoreRepositoryTreeListing {
    func openConfiguredRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        try await openInitializedRepository(repoPath: repoPath, fileLoading: .whenTreeIsEmpty)
    }

    func openEmptyRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        try await openInitializedRepository(repoPath: repoPath, fileLoading: .always)
    }

    func openAdoptedRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        try await openInitializedRepository(repoPath: repoPath, fileLoading: .never)
    }

    private func openInitializedRepository(
        repoPath: String,
        fileLoading: CurrentCategoryFileLoading
    ) async throws -> RepositoryOpeningResult {
        let config = RepoConfigSnapshot(coreConfig: try loadOpeningCoreConfig(repoPath: repoPath))
        let tree = try await listTree(repoPath: repoPath, locale: config.locale)
        let currentCategory = loadOpeningCurrentCategoryFiles(
            repoPath: repoPath,
            tree: tree,
            shouldLoad: fileLoading.shouldLoadFiles(for: tree),
            listFiles: listOpeningCoreFiles,
            mapError: openingCurrentListErrorMapping
        )
        return RepositoryOpeningResult(
            config: config,
            tree: tree,
            currentCategoryFiles: currentCategory.files,
            currentCategoryListError: currentCategory.errorMapping,
            isReadOnly: RepositoryOpeningAccessState.isReadOnly(repoPath: repoPath)
        )
    }

    func listTree(repoPath: String, locale: String) async throws -> RepositoryTreeNodeSnapshot {
        let treeJSON = try await listTreeJSON(repoPath: repoPath, locale: locale)
        return try decodeOpeningTreeSnapshot(treeJSON)
    }
}

private enum RepositoryOpeningAccessState {
    static func isReadOnly(repoPath: String) -> Bool {
        !FileManager.default.isWritableFile(atPath: repoPath)
    }
}

private func loadOpeningCoreConfig(repoPath: String) throws -> RepoConfig {
    try loadConfig(repoPath: repoPath)
}

private func listOpeningCoreFiles(repoPath: String, filter: FileFilterSnapshot) throws -> [FileEntrySnapshot] {
    try listFiles(repoPath: repoPath, filter: FileFilter(filter)).map { coreEntry in
        FileEntrySnapshot(coreEntry: coreEntry) { path, sourcePath in
            FileAvailabilityResolverForOpening.availability(
                repoPath: repoPath,
                relativePath: path,
                sourcePath: sourcePath
            )
        }
    }
}

private enum FileAvailabilityResolverForOpening {
    static func availability(repoPath: String, relativePath: String, sourcePath: String?) -> FileAvailabilitySnapshot {
        if isICloudPlaceholder(relativePath) || sourcePath.map(isICloudPlaceholder) == true {
            return .iCloudPlaceholder
        }

        let fileURL = URL(fileURLWithPath: repoPath, isDirectory: true).appendingPathComponent(relativePath)
        return FileManager.default.fileExists(atPath: fileURL.path) ? .available : .missing
    }

    private static func isICloudPlaceholder(_ path: String) -> Bool {
        path.hasSuffix(".icloud") || path.contains(".icloud/")
    }
}

private enum CurrentCategoryFileLoading {
    case never
    case whenTreeIsEmpty
    case always

    func shouldLoadFiles(for tree: RepositoryTreeNodeSnapshot) -> Bool {
        switch self {
        case .never:
            return false
        case .whenTreeIsEmpty:
            return tree.totalFileCount == 0
        case .always:
            return true
        }
    }
}

func loadOpeningCurrentCategoryFiles(
    repoPath: String,
    tree: RepositoryTreeNodeSnapshot,
    shouldLoad: Bool,
    listFiles: (String, FileFilterSnapshot) throws -> [FileEntrySnapshot],
    mapError: (Error) -> CoreErrorMappingSnapshot
) -> RepositoryCurrentCategoryFilesResult {
    guard shouldLoad else {
        return RepositoryCurrentCategoryFilesResult(files: [], errorMapping: nil)
    }

    do {
        let files = try listFiles(repoPath, FileFilterSnapshot.currentCategory(tree.defaultCategory))
        return RepositoryCurrentCategoryFilesResult(files: files, errorMapping: nil)
    } catch {
        return RepositoryCurrentCategoryFilesResult(files: [], errorMapping: mapError(error))
    }
}

private func openingCurrentListErrorMapping(_ error: Error) -> CoreErrorMappingSnapshot {
    if let coreError = error as? CoreError {
        return CoreErrorMappingSnapshot(coreMapping: mapCoreErrorFromCore(coreError))
    }

    return CoreErrorMappingSnapshot(coreMapping: mapCoreErrorFromCore(
        CoreError.Internal(message: error.localizedDescription)
    ))
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
