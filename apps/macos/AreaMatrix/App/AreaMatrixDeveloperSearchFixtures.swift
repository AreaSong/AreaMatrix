import Foundation

#if DEBUG
enum DeveloperSearchScenarioFixture {
    static let repoPath = AreaMatrixPreviewFixtures.repositoryPath

    static func request(
        query: String = "invoice",
        filters: SearchFilterStateSnapshot = .empty,
        mode: SearchModeSnapshot = .normal
    ) -> SearchQueryRequestSnapshot {
        SearchQueryRequestSnapshot(
            query: query,
            scope: .all,
            currentPath: nil,
            category: nil,
            filters: filters,
            sort: .relevance,
            limit: 50,
            offset: 0,
            mode: mode
        )
    }

    static var filteredRequest: SearchQueryRequestSnapshot {
        request(
            query: "invoice",
            filters: SearchFilterStateSnapshot(
                category: "finance",
                fileKind: "pdf",
                tags: ["quarterly"],
                tagMatchMode: .all,
                importedAfter: nil,
                importedBefore: nil,
                modifiedAfter: 1_778_000_000,
                modifiedBefore: nil,
                storageMode: .copied,
                includeDeleted: false
            )
        )
    }

    static var queryErrorRequest: SearchQueryRequestSnapshot {
        request(query: "kindd:pdf invoice")
    }

    static var queryDiagnostic: SearchQueryDiagnosticSnapshot {
        SearchQueryDiagnosticSnapshot(
            kindDisplayName: L10n.string("Unknown field"),
            severityDisplayName: L10n.string("Error"),
            message: L10n.resolve(L10n.verbatim("Unknown field `kindd`", reason: .technicalDetail)),
            token: "kindd",
            start: 0,
            end: 5,
            suggestion: "kind",
            isErrorSeverity: true
        )
    }

    static var savedSearch: SavedSearchSnapshot {
        SavedSearchSnapshot(
            id: 701,
            name: "Quarterly invoices",
            query: SavedSearchQuerySnapshot(request: filteredRequest),
            icon: "doc.text.magnifyingglass",
            color: nil,
            pinned: true,
            createdAt: 1_778_738_400,
            updatedAt: 1_778_738_400
        )
    }

    static var semanticPage: SemanticSearchResultPageSnapshot {
        let primary = semanticResult(
            file: file(id: 801, name: "invoice-q2.pdf"),
            snippet: "Q2 invoice and payment summary"
        )
        let secondary = semanticResult(
            file: file(id: 802, name: "vendor-renewal.pdf"),
            snippet: "Renewal document with recurring billing terms"
        )
        let normalOnly = semanticResult(
            file: file(id: 803, name: "invoice-notes.txt"),
            snippet: "invoice follow-up notes"
        )

        return SemanticSearchResultPageSnapshot(
            query: "recurring vendor invoices",
            semanticTotalCount: 3,
            normalTotalCount: 2,
            semanticMatches: [
                SemanticSearchMatchSnapshot(
                    result: primary,
                    relevance: 0.96,
                    matchedReason: "The filename and summary describe recurring invoice payments.",
                    usedFields: [.fileName, .aiSummary],
                    route: .local,
                    alsoMatchedNormalSearch: true,
                    callLogID: 901,
                    privacyRuleID: nil
                ),
                SemanticSearchMatchSnapshot(
                    result: secondary,
                    relevance: 0.84,
                    matchedReason: "The note summary matches vendor renewal and billing concepts.",
                    usedFields: [.noteSummary, .repoRelativePath],
                    route: .local,
                    alsoMatchedNormalSearch: false,
                    callLogID: 901,
                    privacyRuleID: nil
                )
            ],
            normalMatches: [
                SemanticNormalSearchMatchSnapshot(result: primary, dedupedBySemantic: true),
                SemanticNormalSearchMatchSnapshot(result: normalOnly, dedupedBySemantic: false)
            ],
            dedupedNormalCount: 1,
            indexStatus: .ready,
            route: .local,
            fallbackReason: nil,
            fallbackMessage: nil,
            callLogID: 901,
            privacyRuleID: nil,
            lowConfidence: false
        )
    }

    static func searchPage(for request: SearchQueryRequestSnapshot) -> SearchResultPageSnapshot {
        SearchResultPageSnapshot(
            query: request.query,
            totalCount: 12,
            results: [],
            diagnostics: [],
            indexStatus: .ready,
            semanticPage: nil
        )
    }

    private static func file(id: Int64, name: String) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: "finance/invoices/\(name)",
            originalName: name,
            currentName: name,
            category: "finance",
            sizeBytes: 32768 + id,
            hashSha256: "developer-search-\(id)",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_778_738_400 - id,
            updatedAt: 1_778_738_400 - id
        )
    }

    private static func semanticResult(
        file: FileEntrySnapshot,
        snippet: String
    ) -> SearchFileResultSnapshot {
        SearchFileResultSnapshot(
            file: file,
            score: 0.9,
            matches: [
                SearchMatchSnapshot(
                    fieldDisplayName: "Name",
                    kindDisplayName: "Exact match",
                    snippet: snippet
                )
            ],
            noteSnippet: snippet
        )
    }
}

actor DeveloperSearchCoreFixture: CoreSavedSearchCRUD, CoreSearchQuerying {
    private var savedSearches: [SavedSearchSnapshot]

    init(savedSearches: [SavedSearchSnapshot] = [DeveloperSearchScenarioFixture.savedSearch]) {
        self.savedSearches = savedSearches
    }

    func createSavedSearch(
        repoPath _: String,
        request: CreateSavedSearchRequestSnapshot
    ) async throws -> SavedSearchSnapshot {
        let nextID = (savedSearches.map(\.id).max() ?? 700) + 1
        let saved = SavedSearchSnapshot(
            id: nextID,
            name: request.name,
            query: request.query,
            icon: request.icon,
            color: request.color,
            pinned: request.pinned,
            createdAt: 1_778_738_400,
            updatedAt: 1_778_738_400
        )
        savedSearches.append(saved)
        return saved
    }

    func updateSavedSearch(
        repoPath _: String,
        request: UpdateSavedSearchRequestSnapshot
    ) async throws -> SavedSearchSnapshot {
        let saved = SavedSearchSnapshot(
            id: request.id,
            name: request.name,
            query: request.query,
            icon: request.icon,
            color: request.color,
            pinned: request.pinned,
            createdAt: savedSearches.first(where: { $0.id == request.id })?.createdAt ?? 1_778_738_400,
            updatedAt: 1_778_738_401
        )
        if let index = savedSearches.firstIndex(where: { $0.id == request.id }) {
            savedSearches[index] = saved
        } else {
            savedSearches.append(saved)
        }
        return saved
    }

    func deleteSavedSearch(repoPath _: String, savedSearchID: Int64) async throws {
        savedSearches.removeAll { $0.id == savedSearchID }
    }

    func listSavedSearches(repoPath _: String) async throws -> [SavedSearchSnapshot] {
        savedSearches
    }

    func searchFiles(
        repoPath _: String,
        request: SearchQueryRequestSnapshot
    ) async throws -> SearchResultPageSnapshot {
        DeveloperSearchScenarioFixture.searchPage(for: request)
    }
}
#endif
