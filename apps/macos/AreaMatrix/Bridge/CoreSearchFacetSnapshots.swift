import AreaMatrixCoreBridgeContract
import Foundation

typealias CoreSearchFiltering = AreaMatrixCoreBridgeContract.CoreSearchFiltering
typealias SearchScopeSnapshot = AreaMatrixCoreBridgeContract.SearchScopeSnapshot
typealias SearchTagMatchModeSnapshot = AreaMatrixCoreBridgeContract.SearchTagMatchModeSnapshot
typealias SearchStorageModeSnapshot = AreaMatrixCoreBridgeContract.SearchStorageModeSnapshot
typealias SearchFilterStateSnapshot = AreaMatrixCoreBridgeContract.SearchFilterStateSnapshot
typealias SearchFacetRequestSnapshot = AreaMatrixCoreBridgeContract.SearchFacetRequestSnapshot
typealias SearchFacetCountSnapshot = AreaMatrixCoreBridgeContract.SearchFacetCountSnapshot
typealias SearchStorageModeFacetCountSnapshot = AreaMatrixCoreBridgeContract.SearchStorageModeFacetCountSnapshot
typealias SearchDateFacetBoundsSnapshot = AreaMatrixCoreBridgeContract.SearchDateFacetBoundsSnapshot
typealias SearchFacetsSnapshot = AreaMatrixCoreBridgeContract.SearchFacetsSnapshot

extension SearchStorageModeSnapshot {
    var displayName: String {
        switch self {
        case .moved:
            L10n.string("Moved")
        case .copied:
            L10n.string("Copied")
        case .indexed:
            L10n.string("Indexed")
        }
    }
}

extension SearchFacetRequestSnapshot {
    static func pageFeature(
        query: String,
        scope: SearchScopeSnapshot,
        sidebarRow: RepositorySidebarRowSnapshot,
        filters: SearchFilterStateSnapshot
    ) -> SearchFacetRequestSnapshot {
        SearchFacetRequestSnapshot(
            query: query,
            scope: scope,
            currentPath: scope == .current ? sidebarRow.pathFilterPrefix : nil,
            category: scope == .current ? sidebarRow.categoryForFileList : nil,
            filters: filters
        )
    }
}

extension CoreBridge: CoreSearchFiltering {
    func listFilterFacets(repoPath: String, request: SearchFacetRequestSnapshot) async throws -> SearchFacetsSnapshot {
        let facets = try await Task.detached(priority: .userInitiated) {
            try self.generatedAdapter.listFilterFacets(
                repoPath: repoPath,
                query: SearchFacetQuery(request)
            )
        }.value
        return SearchFacetsSnapshot(coreFacets: facets)
    }
}

extension SearchFacetQuery {
    init(_ snapshot: SearchFacetRequestSnapshot) {
        let filters = snapshot.filters
        self.init(
            query: snapshot.query,
            scope: SearchScope(snapshot.scope),
            currentPath: snapshot.currentPath,
            category: filters.category ?? snapshot.category,
            fileKind: filters.fileKind,
            tags: filters.tags,
            tagMatchMode: SearchTagMatchMode(filters.tagMatchMode),
            importedAfter: filters.importedAfter,
            importedBefore: filters.importedBefore,
            modifiedAfter: filters.modifiedAfter,
            modifiedBefore: filters.modifiedBefore,
            storageMode: filters.storageMode.map(StorageMode.init),
            includeDeleted: filters.includeDeleted
        )
    }
}

extension SearchTagMatchMode {
    init(_ snapshot: SearchTagMatchModeSnapshot) {
        switch snapshot {
        case .any:
            self = .any
        case .all:
            self = .all
        }
    }
}

extension StorageMode {
    init(_ snapshot: SearchStorageModeSnapshot) {
        switch snapshot {
        case .moved:
            self = .moved
        case .copied:
            self = .copied
        case .indexed:
            self = .indexed
        }
    }
}

extension SearchStorageModeSnapshot {
    init(coreMode: StorageMode) {
        switch coreMode {
        case .moved:
            self = .moved
        case .copied:
            self = .copied
        case .indexed:
            self = .indexed
        }
    }
}

extension SearchFacetsSnapshot {
    init(coreFacets: SearchFacets) {
        self.init(
            query: coreFacets.query,
            totalCount: coreFacets.totalCount,
            categories: coreFacets.categories.map(SearchFacetCountSnapshot.init(coreCount:)),
            fileKinds: coreFacets.fileKinds.map(SearchFacetCountSnapshot.init(coreCount:)),
            tags: coreFacets.tags.map(SearchFacetCountSnapshot.init(coreCount:)),
            storageModes: coreFacets.storageModes.map(SearchStorageModeFacetCountSnapshot.init(coreCount:)),
            dateBounds: SearchDateFacetBoundsSnapshot(coreBounds: coreFacets.dateBounds),
            activeFilterCount: coreFacets.activeFilterCount
        )
    }
}

private extension SearchFacetCountSnapshot {
    init(coreCount: SearchFacetCount) {
        self.init(
            value: coreCount.value,
            label: coreCount.label,
            count: coreCount.count,
            selected: coreCount.selected,
            disabled: coreCount.disabled
        )
    }
}

private extension SearchStorageModeFacetCountSnapshot {
    init(coreCount: SearchStorageModeFacetCount) {
        self.init(
            value: SearchStorageModeSnapshot(coreMode: coreCount.value),
            label: coreCount.label,
            count: coreCount.count,
            selected: coreCount.selected,
            disabled: coreCount.disabled
        )
    }
}

private extension SearchDateFacetBoundsSnapshot {
    init(coreBounds: SearchDateFacetBounds) {
        self.init(
            oldestImportedAt: coreBounds.oldestImportedAt,
            newestImportedAt: coreBounds.newestImportedAt,
            oldestModifiedAt: coreBounds.oldestModifiedAt,
            newestModifiedAt: coreBounds.newestModifiedAt
        )
    }
}
