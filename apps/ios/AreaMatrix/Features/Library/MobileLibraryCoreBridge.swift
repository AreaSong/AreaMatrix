import Foundation

protocol MobileLibraryCoreBridge: Sendable {
    func listFiles(repoPath: String, filter: MobileLibraryFileFilter) async throws -> [MobileLibraryFile]
    func listTree(repoPath: String, locale: String) async throws -> MobileLibraryTreeNode
}

struct MobileLibraryFileFilter: Equatable {
    var category: String?
    var includeDeleted: Bool?
    var importedAfter: Int64?
    var importedBefore: Int64?
    var limit: Int64
    var offset: Int64

    static func page(category: String?, limit: Int64 = 50, offset: Int64 = 0) -> MobileLibraryFileFilter {
        MobileLibraryFileFilter(
            category: category,
            includeDeleted: false,
            importedAfter: nil,
            importedBefore: nil,
            limit: limit,
            offset: offset
        )
    }
}

enum MobileLibraryFileAvailability: String, Equatable {
    case available = "Available"
    case missing = "Missing"

    var statusText: String {
        switch self {
        case .available:
            "Available"
        case .missing:
            "Missing"
        }
    }
}

struct MobileLibraryFile: Equatable, Identifiable {
    var id: Int64
    var path: String
    var originalName: String
    var currentName: String
    var category: String
    var sizeBytes: Int64
    var hashSha256: String
    var storageMode: String
    var origin: String
    var sourcePath: String?
    var availability: MobileLibraryFileAvailability
    var importedAt: Int64
    var updatedAt: Int64

    var categoryPath: String {
        if category.isEmpty {
            return path
        }
        return "\(category) / \(path)"
    }

    var needsReview: Bool {
        availability != .available
    }
}

struct MobileLibraryTreeNode: Equatable, Identifiable {
    var slug: String
    var displayName: String
    var kind: String
    var relativePath: String
    var fileCount: Int64
    var sizeBytes: Int64
    var depth: Int64
    var children: [MobileLibraryTreeNode]

    var id: String {
        relativePath.isEmpty ? slug : relativePath
    }

    var totalFileCount: Int64 {
        max(fileCount, children.reduce(0) { $0 + $1.totalFileCount })
    }

    var categoryRows: [MobileLibraryCategoryRow] {
        let nodes = children.isEmpty ? [self] : children
        return nodes.map { node in
            MobileLibraryCategoryRow(
                id: node.id,
                displayName: node.displayName,
                category: node.categoryFilter,
                fileCount: node.totalFileCount
            )
        }
    }

    private var categoryFilter: String? {
        if slug == "__root__" || relativePath.isEmpty {
            return nil
        }
        return relativePath.split(separator: "/").first.map(String.init) ?? slug
    }
}

struct MobileLibraryCategoryRow: Equatable, Identifiable {
    var id: String
    var displayName: String
    var category: String?
    var fileCount: Int64
}

enum MobileLibrarySort: String, CaseIterable, Identifiable {
    case recentlyUpdated
    case name
    case size

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .recentlyUpdated:
            "Updated"
        case .name:
            "Name"
        case .size:
            "Size"
        }
    }
}

enum MobileLibraryQueryError: Error, Equatable {
    case repoNotInitialized(String)
    case database(String)
    case unavailable(String)

    var message: String {
        switch self {
        case .repoNotInitialized:
            "This folder is not an initialized AreaMatrix repository."
        case let .database(message):
            message.isEmpty ? "Repository metadata could not be read." : message
        case let .unavailable(message):
            message.isEmpty ? "Repository data is unavailable." : message
        }
    }

    static func map(_ error: Error) -> MobileLibraryQueryError {
        if let queryError = error as? MobileLibraryQueryError {
            return queryError
        }
        if let connectionError = error as? MobileRepositoryConnectionError {
            return mapConnectionError(connectionError)
        }
        return .unavailable(error.localizedDescription)
    }

    private static func mapConnectionError(_ error: MobileRepositoryConnectionError) -> MobileLibraryQueryError {
        switch error {
        case let .invalidRepository(path):
            return .repoNotInitialized(path)
        case let .unavailable(message):
            if message.localizedCaseInsensitiveContains("db") {
                return .database(message)
            }
            return .unavailable(message)
        case let .invalidPath(path), let .selectedFile(path):
            return .repoNotInitialized(path)
        case let .permissionDenied(path), let .accessExpired(path), let .iCloudPlaceholder(path):
            return .unavailable(path)
        }
    }
}

extension LiveMobileRepositoryCoreBridge: MobileLibraryCoreBridge {
    func listFiles(repoPath: String, filter: MobileLibraryFileFilter) async throws -> [MobileLibraryFile] {
        try MobileLibraryCoreFFIClient().listFiles(repoPath: repoPath, filter: filter)
    }

    func listTree(repoPath: String, locale: String) async throws -> MobileLibraryTreeNode {
        let json = try MobileLibraryCoreFFIClient().listTreeJSON(repoPath: repoPath, locale: locale)
        return try MobileLibraryTreeDecoder.decode(json)
    }
}

enum MobileLibraryTreeDecoder {
    static func decode(_ json: String) throws -> MobileLibraryTreeNode {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(DecodedMobileLibraryTreeNode.self, from: Data(json.utf8))
        return MobileLibraryTreeNode(decoded)
    }
}

private struct DecodedMobileLibraryTreeNode: Decodable {
    var slug: String
    var displayName: String
    var kind: String
    var relativePath: String
    var fileCount: Int64
    var sizeBytes: Int64
    var depth: Int64
    var children: [DecodedMobileLibraryTreeNode]

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
        children = try container.decodeIfPresent([DecodedMobileLibraryTreeNode].self, forKey: .children) ?? []
    }
}

private extension MobileLibraryTreeNode {
    init(_ decoded: DecodedMobileLibraryTreeNode) {
        self.init(
            slug: decoded.slug,
            displayName: decoded.displayName,
            kind: decoded.kind,
            relativePath: decoded.relativePath,
            fileCount: decoded.fileCount,
            sizeBytes: decoded.sizeBytes,
            depth: decoded.depth,
            children: decoded.children.map(MobileLibraryTreeNode.init)
        )
    }
}
