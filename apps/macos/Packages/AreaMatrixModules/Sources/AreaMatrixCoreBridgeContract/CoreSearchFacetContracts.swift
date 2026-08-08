/// Stable search-facet capability surface consumed by feature models.
///
/// Search execution and generated DTO conversion remain App-owned; this
/// module publishes only the value contract needed by the feature boundary.
public protocol CoreSearchFiltering: Sendable {
    func listFilterFacets(repoPath: String, request: SearchFacetRequestSnapshot) async throws -> SearchFacetsSnapshot
}

public enum SearchScopeSnapshot: String, CaseIterable, Equatable, Identifiable, Sendable {
    case all
    case current

    public var id: String {
        rawValue
    }
}

public enum SearchTagMatchModeSnapshot: String, Equatable, Sendable {
    case any
    case all
}

public enum SearchStorageModeSnapshot: String, CaseIterable, Equatable, Identifiable, Sendable {
    case moved
    case copied
    case indexed

    public var id: String {
        rawValue
    }
}

public struct SearchFilterStateSnapshot: Equatable, Sendable {
    public var category: String?
    public var fileKind: String?
    public var tags: [String]
    public var tagMatchMode: SearchTagMatchModeSnapshot
    public var importedAfter: Int64?
    public var importedBefore: Int64?
    public var modifiedAfter: Int64?
    public var modifiedBefore: Int64?
    public var storageMode: SearchStorageModeSnapshot?
    public var includeDeleted: Bool

    public init(
        category: String?,
        fileKind: String?,
        tags: [String],
        tagMatchMode: SearchTagMatchModeSnapshot,
        importedAfter: Int64?,
        importedBefore: Int64?,
        modifiedAfter: Int64?,
        modifiedBefore: Int64?,
        storageMode: SearchStorageModeSnapshot?,
        includeDeleted: Bool
    ) {
        self.category = category
        self.fileKind = fileKind
        self.tags = tags
        self.tagMatchMode = tagMatchMode
        self.importedAfter = importedAfter
        self.importedBefore = importedBefore
        self.modifiedAfter = modifiedAfter
        self.modifiedBefore = modifiedBefore
        self.storageMode = storageMode
        self.includeDeleted = includeDeleted
    }

    public static let empty = SearchFilterStateSnapshot(
        category: nil,
        fileKind: nil,
        tags: [],
        tagMatchMode: .any,
        importedAfter: nil,
        importedBefore: nil,
        modifiedAfter: nil,
        modifiedBefore: nil,
        storageMode: nil,
        includeDeleted: false
    )

    public var isEmpty: Bool {
        activeFilterCount == 0
    }

    public var activeFilterCount: Int64 {
        var count: Int64 = 0
        if category != nil { count += 1 }
        if fileKind != nil { count += 1 }
        if !tags.isEmpty { count += 1 }
        if importedAfter != nil || importedBefore != nil { count += 1 }
        if modifiedAfter != nil || modifiedBefore != nil { count += 1 }
        if storageMode != nil { count += 1 }
        if includeDeleted { count += 1 }
        return count
    }

    public var taskKey: String {
        var parts: [String] = []
        parts.append(category ?? "")
        parts.append(fileKind ?? "")
        parts.append(tags.joined(separator: ","))
        parts.append(tagMatchMode.rawValue)
        parts.append(importedAfter.map(String.init) ?? "")
        parts.append(importedBefore.map(String.init) ?? "")
        parts.append(modifiedAfter.map(String.init) ?? "")
        parts.append(modifiedBefore.map(String.init) ?? "")
        parts.append(storageMode?.rawValue ?? "")
        parts.append(includeDeleted ? "include-deleted" : "visible-only")
        return parts.joined(separator: "|")
    }
}

public struct SearchFacetRequestSnapshot: Equatable, Sendable {
    public var query: String
    public var scope: SearchScopeSnapshot
    public var currentPath: String?
    public var category: String?
    public var filters: SearchFilterStateSnapshot

    public init(
        query: String,
        scope: SearchScopeSnapshot,
        currentPath: String?,
        category: String?,
        filters: SearchFilterStateSnapshot
    ) {
        self.query = query
        self.scope = scope
        self.currentPath = currentPath
        self.category = category
        self.filters = filters
    }
}

public struct SearchFacetCountSnapshot: Equatable, Identifiable, Sendable {
    public var value: String
    public var label: String
    public var count: Int64
    public var selected: Bool
    public var disabled: Bool

    public init(value: String, label: String, count: Int64, selected: Bool, disabled: Bool) {
        self.value = value
        self.label = label
        self.count = count
        self.selected = selected
        self.disabled = disabled
    }

    public var id: String {
        value
    }
}

public struct SearchStorageModeFacetCountSnapshot: Equatable, Identifiable, Sendable {
    public var value: SearchStorageModeSnapshot
    public var label: String
    public var count: Int64
    public var selected: Bool
    public var disabled: Bool

    public init(
        value: SearchStorageModeSnapshot,
        label: String,
        count: Int64,
        selected: Bool,
        disabled: Bool
    ) {
        self.value = value
        self.label = label
        self.count = count
        self.selected = selected
        self.disabled = disabled
    }

    public var id: String {
        value.rawValue
    }
}

public struct SearchDateFacetBoundsSnapshot: Equatable, Sendable {
    public var oldestImportedAt: Int64?
    public var newestImportedAt: Int64?
    public var oldestModifiedAt: Int64?
    public var newestModifiedAt: Int64?

    public init(
        oldestImportedAt: Int64?,
        newestImportedAt: Int64?,
        oldestModifiedAt: Int64?,
        newestModifiedAt: Int64?
    ) {
        self.oldestImportedAt = oldestImportedAt
        self.newestImportedAt = newestImportedAt
        self.oldestModifiedAt = oldestModifiedAt
        self.newestModifiedAt = newestModifiedAt
    }
}

public struct SearchFacetsSnapshot: Equatable, Sendable {
    public var query: String
    public var totalCount: Int64
    public var categories: [SearchFacetCountSnapshot]
    public var fileKinds: [SearchFacetCountSnapshot]
    public var tags: [SearchFacetCountSnapshot]
    public var storageModes: [SearchStorageModeFacetCountSnapshot]
    public var dateBounds: SearchDateFacetBoundsSnapshot
    public var activeFilterCount: Int64

    public init(
        query: String,
        totalCount: Int64,
        categories: [SearchFacetCountSnapshot],
        fileKinds: [SearchFacetCountSnapshot],
        tags: [SearchFacetCountSnapshot],
        storageModes: [SearchStorageModeFacetCountSnapshot],
        dateBounds: SearchDateFacetBoundsSnapshot,
        activeFilterCount: Int64
    ) {
        self.query = query
        self.totalCount = totalCount
        self.categories = categories
        self.fileKinds = fileKinds
        self.tags = tags
        self.storageModes = storageModes
        self.dateBounds = dateBounds
        self.activeFilterCount = activeFilterCount
    }
}
