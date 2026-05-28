import Foundation

enum ClassifyReasonSnapshot: String, Equatable {
    case keyword = "Keyword"
    case `extension` = "Extension"
    case aiPredicted = "AiPredicted"
    case `default` = "Default"

    var displayLabel: String {
        switch self {
        case .keyword:
            "keyword"
        case .extension:
            "extension"
        case .aiPredicted:
            "AI"
        case .default:
            "default"
        }
    }
}

struct ClassifyResultSnapshot: Equatable {
    var category: String
    var suggestedName: String
    var reason: ClassifyReasonSnapshot
    var confidence: Float

    var confidencePercent: Int {
        Int((confidence * 100).rounded())
    }
}

extension ClassifyResultSnapshot {
    init(coreResult: ClassifyResult) {
        category = coreResult.category
        suggestedName = coreResult.suggestedName
        reason = ClassifyReasonSnapshot(coreReason: coreResult.reason)
        confidence = coreResult.confidence
    }
}

private extension ClassifyReasonSnapshot {
    init(coreReason: ClassifyReason) {
        switch coreReason {
        case .keyword:
            self = .keyword
        case .extension:
            self = .extension
        case .aiPredicted:
            self = .aiPredicted
        case .default:
            self = .default
        }
    }
}

extension ScanSessionSnapshot {
    init(coreSession: ScanSession) {
        id = coreSession.id
        kind = ScanSessionKindSnapshot(coreKind: coreSession.kind)
        status = ScanSessionStatusSnapshot(coreStatus: coreSession.status)
        lastPath = coreSession.lastPath
        inserted = coreSession.inserted
        updated = coreSession.updated
        skipped = coreSession.skipped
        startedAt = coreSession.startedAt
        updatedAt = coreSession.updatedAt
        finishedAt = coreSession.finishedAt
        errors = coreSession.errors
    }
}

private extension ScanSessionKindSnapshot {
    init(coreKind: ScanSessionKind) {
        switch coreKind {
        case .adopt:
            self = .adopt
        case .reindex:
            self = .reindex
        }
    }
}

private extension ScanSessionStatusSnapshot {
    init(coreStatus: ScanSessionStatus) {
        switch coreStatus {
        case .running:
            self = .running
        case .completed:
            self = .completed
        case .paused:
            self = .paused
        case .failed:
            self = .failed
        case .interrupted:
            self = .interrupted
        }
    }
}

extension RepoPathValidationSnapshot {
    init(coreValidation: RepoPathValidation) {
        let environment = RepositoryPathEnvironmentSnapshot.inspect(repoPath: coreValidation.repoPath)

        repoPath = coreValidation.repoPath
        exists = coreValidation.exists
        isDirectory = coreValidation.isDirectory
        isReadable = coreValidation.isReadable
        isWritable = coreValidation.isWritable
        isEmpty = coreValidation.isEmpty
        isInitialized = coreValidation.isInitialized
        isInsideAreaMatrix = coreValidation.isInsideAreaMatrix
        isICloudPath = coreValidation.isIcloudPath
        hasUnfinishedScanSession = coreValidation.hasUnfinishedScanSession
        availableCapacityBytes = environment.availableCapacityBytes
        isExternalVolume = environment.isExternalVolume
        recommendedMode = coreValidation.recommendedMode.map(RepoInitModeSnapshot.init(coreMode:))
        issues = coreValidation.issues.map(RepoPathIssueSnapshot.init(coreIssue:))
    }
}

private struct RepositoryPathEnvironmentSnapshot {
    var availableCapacityBytes: Int64?
    var isExternalVolume: Bool?

    static func inspect(repoPath: String) -> RepositoryPathEnvironmentSnapshot {
        do {
            let keys: Set<URLResourceKey> = [
                .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey, .volumeIsInternalKey
            ]
            let values = try URL(fileURLWithPath: repoPath).resourceValues(forKeys: keys)
            return RepositoryPathEnvironmentSnapshot(
                availableCapacityBytes: values.volumeAvailableCapacityForImportantUsage ??
                    values.volumeAvailableCapacity.map(Int64.init),
                isExternalVolume: values.volumeIsInternal.map { !$0 }
            )
        } catch {
            return RepositoryPathEnvironmentSnapshot(availableCapacityBytes: nil, isExternalVolume: nil)
        }
    }
}

private extension RepoInitModeSnapshot {
    init(coreMode: RepoInitMode) {
        switch coreMode {
        case .createEmpty:
            self = .createEmpty
        case .adoptExisting:
            self = .adoptExisting
        }
    }
}

private extension RepoPathIssueSnapshot {
    init(coreIssue: RepoPathIssue) {
        switch coreIssue {
        case .missingPath:
            self = .missingPath
        case .notDirectory:
            self = .notDirectory
        case .notReadable:
            self = .notReadable
        case .notWritable:
            self = .notWritable
        case .nonEmptyDirectory:
            self = .nonEmptyDirectory
        case .alreadyInitialized:
            self = .alreadyInitialized
        case .insideAreaMatrix:
            self = .insideAreaMatrix
        case .iCloudPath:
            self = .iCloudPath
        case .unfinishedScanSession:
            self = .unfinishedScanSession
        }
    }
}

protocol CoreSearchFiltering: Sendable {
    func listFilterFacets(repoPath: String, request: SearchFacetRequestSnapshot) async throws -> SearchFacetsSnapshot
}

enum SearchTagMatchModeSnapshot: String, Equatable {
    case any
    case all
}

enum SearchStorageModeSnapshot: String, CaseIterable, Equatable, Identifiable {
    case moved
    case copied
    case indexed

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .moved:
            "Moved"
        case .copied:
            "Copied"
        case .indexed:
            "Indexed"
        }
    }
}

struct SearchFilterStateSnapshot: Equatable {
    var category: String?
    var fileKind: String?
    var tags: [String]
    var tagMatchMode: SearchTagMatchModeSnapshot
    var importedAfter: Int64?
    var importedBefore: Int64?
    var modifiedAfter: Int64?
    var modifiedBefore: Int64?
    var storageMode: SearchStorageModeSnapshot?
    var includeDeleted: Bool

    static let empty = SearchFilterStateSnapshot(
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

    var isEmpty: Bool {
        activeFilterCount == 0
    }

    var activeFilterCount: Int64 {
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

    var taskKey: String {
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

struct SearchFacetRequestSnapshot: Equatable {
    var query: String
    var scope: SearchScopeSnapshot
    var currentPath: String?
    var category: String?
    var filters: SearchFilterStateSnapshot

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

struct SearchFacetCountSnapshot: Equatable, Identifiable {
    var value: String
    var label: String
    var count: Int64
    var selected: Bool
    var disabled: Bool

    var id: String {
        value
    }
}

struct SearchStorageModeFacetCountSnapshot: Equatable, Identifiable {
    var value: SearchStorageModeSnapshot
    var label: String
    var count: Int64
    var selected: Bool
    var disabled: Bool

    var id: String {
        value.rawValue
    }
}

struct SearchDateFacetBoundsSnapshot: Equatable {
    var oldestImportedAt: Int64?
    var newestImportedAt: Int64?
    var oldestModifiedAt: Int64?
    var newestModifiedAt: Int64?
}

struct SearchFacetsSnapshot: Equatable {
    var query: String
    var totalCount: Int64
    var categories: [SearchFacetCountSnapshot]
    var fileKinds: [SearchFacetCountSnapshot]
    var tags: [SearchFacetCountSnapshot]
    var storageModes: [SearchStorageModeFacetCountSnapshot]
    var dateBounds: SearchDateFacetBoundsSnapshot
    var activeFilterCount: Int64
}

extension CoreBridge: CoreSearchFiltering {
    func listFilterFacets(repoPath: String, request: SearchFacetRequestSnapshot) async throws -> SearchFacetsSnapshot {
        let facets = try await Task.detached(priority: .userInitiated) {
            try AreaMatrix.listFilterFacets(repoPath: repoPath, query: SearchFacetQuery(request))
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
        query = coreFacets.query
        totalCount = coreFacets.totalCount
        categories = coreFacets.categories.map(SearchFacetCountSnapshot.init(coreCount:))
        fileKinds = coreFacets.fileKinds.map(SearchFacetCountSnapshot.init(coreCount:))
        tags = coreFacets.tags.map(SearchFacetCountSnapshot.init(coreCount:))
        storageModes = coreFacets.storageModes.map(SearchStorageModeFacetCountSnapshot.init(coreCount:))
        dateBounds = SearchDateFacetBoundsSnapshot(coreBounds: coreFacets.dateBounds)
        activeFilterCount = coreFacets.activeFilterCount
    }
}

private extension SearchFacetCountSnapshot {
    init(coreCount: SearchFacetCount) {
        value = coreCount.value
        label = coreCount.label
        count = coreCount.count
        selected = coreCount.selected
        disabled = coreCount.disabled
    }
}

private extension SearchStorageModeFacetCountSnapshot {
    init(coreCount: SearchStorageModeFacetCount) {
        value = SearchStorageModeSnapshot(coreMode: coreCount.value)
        label = coreCount.label
        count = coreCount.count
        selected = coreCount.selected
        disabled = coreCount.disabled
    }
}

private extension SearchDateFacetBoundsSnapshot {
    init(coreBounds: SearchDateFacetBounds) {
        oldestImportedAt = coreBounds.oldestImportedAt
        newestImportedAt = coreBounds.newestImportedAt
        oldestModifiedAt = coreBounds.oldestModifiedAt
        newestModifiedAt = coreBounds.newestModifiedAt
    }
}
