import AreaMatrixCoreBridgeContract
@testable import AreaMatrix

extension CoreErrorMappingSnapshot {
    static func generalSettingsMapping(
        kind: CoreErrorKindSnapshot,
        userMessage: String
    ) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: kind,
            userMessage: userMessage,
            suggestedAction: "Retry save",
            rawContext: kind.rawValue
        )
    }

    static func advancedSettingsMapping(
        kind: CoreErrorKindSnapshot,
        userMessage: String
    ) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: kind,
            userMessage: userMessage,
            suggestedAction: "Retry save",
            rawContext: kind.rawValue
        )
    }

    static func integrationsSettingsMapping(
        kind: CoreErrorKindSnapshot,
        userMessage: String
    ) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: kind,
            userMessage: userMessage,
            suggestedAction: kind == .db ? "Retry save" : "Retry status",
            rawContext: "integrations-settings repository-config"
        )
    }
}

extension IntegrationsICloudSnapshot {
    static func testFixture(
        repositoryLocation: IntegrationsRepositoryLocation = .localFolder,
        iCloudStatus: IntegrationsICloudStatus = .unavailable
    ) -> IntegrationsICloudSnapshot {
        IntegrationsICloudSnapshot(
            repositoryLocation: repositoryLocation,
            iCloudStatus: iCloudStatus
        )
    }
}

struct RepositoryTreeNodeTestFixtureOptions {
    var kind: String?
    var relativePath: String?
    var sizeBytes: Int64 = 0
    var depth: Int64?
    var children: [RepositoryTreeNodeSnapshot] = []
}

struct FileEntrySnapshotTestFixtureOptions {
    var originalName: String?
    var sizeBytes: Int64 = 128
    var hashSha256: String?
    var storageMode: String = "Copied"
    var origin: String = "Imported"
    var sourcePath: String?
    var importedAt: Int64 = 1_700_000_000
    var updatedAt: Int64 = 1_700_000_100
    var availability: FileAvailabilitySnapshot = .available
}

struct RepoPathValidationTestFixtureOptions {
    var exists = true
    var isDirectory = true
    var isReadable = true
    var isWritable = true
    var isEmpty = true
    var isInitialized = false
    var isInsideAreaMatrix = false
    var isICloudPath = false
    var hasUnfinishedScanSession = false
    var availableCapacityBytes: Int64? = 1_073_741_824
    var isExternalVolume: Bool? = false
    var recommendedMode: RepoInitModeSnapshot? = .createEmpty
    var issues: [RepoPathIssueSnapshot] = []
}

struct ScanSessionTestFixtureOptions {
    var lastPath: String? = "docs/plan.md"
    var inserted: Int64 = 12
    var updated: Int64 = 2
    var skipped: Int64 = 1
    var startedAt: Int64 = 1_700_000_000
    var updatedAt: Int64 = 1_700_000_010
    var finishedAt: Int64?
    var errors: [String] = []
}

extension SearchFilterStateSnapshot {
    static func testFixture(
        category: String? = nil,
        fileKind: String? = nil,
        tags: [String] = [],
        tagMatchMode: SearchTagMatchModeSnapshot = .any,
        importedAfter: Int64? = nil,
        importedBefore: Int64? = nil,
        modifiedAfter: Int64? = nil,
        modifiedBefore: Int64? = nil,
        storageMode: SearchStorageModeSnapshot? = nil,
        includeDeleted: Bool = false
    ) -> SearchFilterStateSnapshot {
        SearchFilterStateSnapshot(
            category: category,
            fileKind: fileKind,
            tags: tags,
            tagMatchMode: tagMatchMode,
            importedAfter: importedAfter,
            importedBefore: importedBefore,
            modifiedAfter: modifiedAfter,
            modifiedBefore: modifiedBefore,
            storageMode: storageMode,
            includeDeleted: includeDeleted
        )
    }
}

extension SyncResultSnapshot {
    static func testFixture(
        detectedCreates: Int64 = 0,
        detectedRenames: Int64 = 0,
        detectedDeletes: Int64 = 0,
        detectedModifies: Int64 = 0,
        errors: [String] = []
    ) -> SyncResultSnapshot {
        SyncResultSnapshot(
            detectedCreates: detectedCreates,
            detectedRenames: detectedRenames,
            detectedDeletes: detectedDeletes,
            detectedModifies: detectedModifies,
            errors: errors
        )
    }

    static func createdFixture() -> SyncResultSnapshot {
        .testFixture(detectedCreates: 1)
    }

    static func renamedFixture() -> SyncResultSnapshot {
        .testFixture(detectedRenames: 1)
    }

    static func deletedFixture() -> SyncResultSnapshot {
        .testFixture(detectedDeletes: 1)
    }

    static func errorFixture(_ message: String) -> SyncResultSnapshot {
        .testFixture(errors: [message])
    }
}

extension DiagnosticsSnapshotSnapshot {
    static func testFixture(
        snapshotPath: String = ".areamatrix/diagnostics/test-diagnostics.zip",
        createdAt: Int64 = 1_778_000_000,
        warnings: [String] = []
    ) -> DiagnosticsSnapshotSnapshot {
        DiagnosticsSnapshotSnapshot(
            snapshotPath: snapshotPath,
            createdAt: createdAt,
            warnings: warnings
        )
    }
}

extension FileFilterSnapshot {
    static func testFixture(
        category: String? = nil,
        includeDeleted: Bool? = false,
        importedAfter: Int64? = nil,
        importedBefore: Int64? = nil,
        limit: Int64 = 50,
        offset: Int64 = 0
    ) -> FileFilterSnapshot {
        FileFilterSnapshot(
            category: category,
            includeDeleted: includeDeleted,
            importedAfter: importedAfter,
            importedBefore: importedBefore,
            limit: limit,
            offset: offset
        )
    }
}

extension ChangeLogEntrySnapshot {
    static func testFixture(
        id: Int64 = 1,
        fileID: Int64? = 10,
        filename: String = "document.pdf",
        category: String = "docs",
        action: String = "imported",
        detailJSON: String = "{}",
        occurredAt: Int64 = 1_700_000_000
    ) -> ChangeLogEntrySnapshot {
        ChangeLogEntrySnapshot(
            id: id,
            fileID: fileID,
            filename: filename,
            category: category,
            action: action,
            detailJSON: detailJSON,
            occurredAt: occurredAt
        )
    }
}

extension RepositoryTreeNodeSnapshot {
    static func testFixture(
        slug: String,
        displayName: String? = nil,
        fileCount: Int64 = 0,
        options configure: (inout RepositoryTreeNodeTestFixtureOptions) -> Void = { _ in }
    ) -> RepositoryTreeNodeSnapshot {
        var options = RepositoryTreeNodeTestFixtureOptions()
        configure(&options)

        return RepositoryTreeNodeSnapshot(
            slug: slug,
            displayName: displayName ?? slug,
            kind: options.kind ?? (slug == "__root__" ? "RepositoryRoot" : "SystemCategory"),
            relativePath: options.relativePath ?? (slug == "__root__" ? "" : slug),
            fileCount: fileCount,
            sizeBytes: options.sizeBytes,
            depth: options.depth ?? (slug == "__root__" ? 0 : 1),
            children: options.children
        )
    }

    static func testRoot(
        displayName: String = "Repository",
        fileCount: Int64 = 0,
        children: [RepositoryTreeNodeSnapshot] = []
    ) -> RepositoryTreeNodeSnapshot {
        RepositoryTreeNodeSnapshot.testFixture(slug: "__root__", displayName: displayName, fileCount: fileCount) {
            $0.children = children
        }
    }

    static func testCategory(
        _ slug: String,
        fileCount: Int64 = 0,
        children: [RepositoryTreeNodeSnapshot] = [],
        displayName: String? = nil
    ) -> RepositoryTreeNodeSnapshot {
        RepositoryTreeNodeSnapshot.testFixture(slug: slug, displayName: displayName, fileCount: fileCount) {
            $0.children = children
        }
    }

    static func testSubdirectory(
        _ slug: String,
        relativePath: String,
        fileCount: Int64 = 0,
        children: [RepositoryTreeNodeSnapshot] = [],
        kind: String = "Subdir"
    ) -> RepositoryTreeNodeSnapshot {
        RepositoryTreeNodeSnapshot.testFixture(slug: slug, fileCount: fileCount) {
            $0.kind = kind
            $0.relativePath = relativePath
            $0.depth = Int64(relativePath.split(separator: "/").count)
            $0.children = children
        }
    }
}

extension RepositorySidebarRowSnapshot {
    static func testFixture(
        node: RepositoryTreeNodeSnapshot = .testRoot(),
        depth: Int = 0
    ) -> RepositorySidebarRowSnapshot {
        RepositorySidebarRowSnapshot(node: node, depth: depth)
    }
}

extension RepoPathValidationSnapshot {
    static func testFixture(
        repoPath: String,
        options configure: (inout RepoPathValidationTestFixtureOptions) -> Void = { _ in }
    ) -> RepoPathValidationSnapshot {
        var options = RepoPathValidationTestFixtureOptions()
        configure(&options)

        return RepoPathValidationSnapshot(
            repoPath: repoPath,
            exists: options.exists,
            isDirectory: options.isDirectory,
            isReadable: options.isReadable,
            isWritable: options.isWritable,
            isEmpty: options.isEmpty,
            isInitialized: options.isInitialized,
            isInsideAreaMatrix: options.isInsideAreaMatrix,
            isICloudPath: options.isICloudPath,
            hasUnfinishedScanSession: options.hasUnfinishedScanSession,
            availableCapacityBytes: options.availableCapacityBytes,
            isExternalVolume: options.isExternalVolume,
            recommendedMode: options.recommendedMode,
            issues: options.issues
        )
    }
}

extension ScanSessionSnapshot {
    static func testFixture(
        id: Int64 = 42,
        kind: ScanSessionKindSnapshot = .adopt,
        status: ScanSessionStatusSnapshot = .running,
        options configure: (inout ScanSessionTestFixtureOptions) -> Void = { _ in }
    ) -> ScanSessionSnapshot {
        var options = ScanSessionTestFixtureOptions()
        configure(&options)

        return ScanSessionSnapshot(
            id: id,
            kind: kind,
            status: status,
            lastPath: options.lastPath,
            inserted: options.inserted,
            updated: options.updated,
            skipped: options.skipped,
            startedAt: options.startedAt,
            updatedAt: options.updatedAt,
            finishedAt: options.finishedAt,
            errors: options.errors
        )
    }
}

extension FileEntrySnapshot {
    static func testFixture(
        id: Int64,
        path: String,
        currentName: String,
        category: String,
        options configure: (inout FileEntrySnapshotTestFixtureOptions) -> Void = { _ in }
    ) -> FileEntrySnapshot {
        var options = FileEntrySnapshotTestFixtureOptions()
        configure(&options)

        return FileEntrySnapshot(
            id: id,
            path: path,
            originalName: options.originalName ?? currentName,
            currentName: currentName,
            category: category,
            sizeBytes: options.sizeBytes,
            hashSha256: options.hashSha256 ?? "file-entry-\(id)",
            storageMode: options.storageMode,
            origin: options.origin,
            sourcePath: options.sourcePath,
            importedAt: options.importedAt,
            updatedAt: options.updatedAt,
            availability: options.availability
        )
    }
}

extension ClassifyResultSnapshot {
    static func testFixture(
        category: String = "docs",
        suggestedName: String = "source.pdf",
        reason: ClassifyReasonSnapshot = .keyword,
        confidence: Float = 0.9
    ) -> ClassifyResultSnapshot {
        ClassifyResultSnapshot(
            category: category,
            suggestedName: suggestedName,
            reason: reason,
            confidence: confidence
        )
    }
}

extension SearchQueryRequestSnapshot {
    static func testFixture(savedSearchQuery: SavedSearchQuerySnapshot) -> SearchQueryRequestSnapshot {
        SearchQueryRequestSnapshot(savedSearchQuery: savedSearchQuery)
    }

    static func testFixture(
        query: String,
        scope: SearchScopeSnapshot = .all,
        currentPath: String? = nil,
        category: String? = nil,
        filters: SearchFilterStateSnapshot = .empty,
        sort: SearchSortSnapshot = .relevance,
        limit: Int64 = 50,
        offset: Int64 = 0,
        mode: SearchModeSnapshot = .normal
    ) -> SearchQueryRequestSnapshot {
        SearchQueryRequestSnapshot(
            query: query,
            scope: scope,
            currentPath: currentPath,
            category: category,
            filters: filters,
            sort: sort,
            limit: limit,
            offset: offset,
            mode: mode
        )
    }
}
