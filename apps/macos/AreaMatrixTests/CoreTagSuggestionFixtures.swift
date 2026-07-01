@testable import AreaMatrix

extension TagSetSnapshot {
    static func tagAddFixture(fileID: Int64, values: [String]) -> TagSetSnapshot {
        let tags = values.map { value in
            TagRecordSnapshot(
                value: value,
                label: value,
                fileCount: 1,
                selected: true,
                disabled: false,
                updatedAt: 1_700_000_300
            )
        }
        return TagSetSnapshot(
            fileID: fileID,
            fileTags: tags,
            availableTags: tags,
            recentTags: tags,
            updatedAt: 1_700_000_300
        )
    }

    static func tagFilterRegistryFixture(fileID: Int64) -> TagSetSnapshot {
        TagSetSnapshot(
            fileID: fileID,
            fileTags: [],
            availableTags: [
                TagRecordSnapshot(
                    value: "finance",
                    label: "Finance",
                    fileCount: 24,
                    selected: false,
                    disabled: false,
                    updatedAt: 1_700_000_300
                ),
                TagRecordSnapshot(
                    value: "legal",
                    label: "Legal",
                    fileCount: 5,
                    selected: false,
                    disabled: false,
                    updatedAt: 1_700_000_301
                )
            ],
            recentTags: [],
            updatedAt: 1_700_000_301
        )
    }
}

extension TagSuggestionReportSnapshot {
    static func tagSuggestionsFixture(fileID: Int64, existingValues: [String] = []) -> TagSuggestionReportSnapshot {
        TagSuggestionReportSnapshot(
            fileID: fileID,
            suggestions: [
                TagSuggestionSnapshot(
                    suggestionID: "tagSuggestions-finance",
                    slug: "finance",
                    displayName: "Finance",
                    reason: "Matched file name: invoice_2026.pdf",
                    source: .fileName,
                    matchStrength: .strong,
                    alreadyExists: false,
                    needsCreate: false,
                    status: .newTag,
                    selectedByDefault: true,
                    disabledReason: nil
                ),
                TagSuggestionSnapshot(
                    suggestionID: "tagSuggestions-tax",
                    slug: "tax",
                    displayName: "Tax",
                    reason: "Matched path: finance/tax",
                    source: .path,
                    matchStrength: .weak,
                    alreadyExists: false,
                    needsCreate: true,
                    status: .newTag,
                    selectedByDefault: false,
                    disabledReason: nil
                )
            ],
            tagSet: .tagAddFixture(fileID: fileID, values: existingValues),
            contentsRead: false,
            aiUsed: false,
            networkUsed: false
        )
    }

    static func tagSuggestionsEmptyFixture(fileID: Int64,
                                           existingValues: [String] = []) -> TagSuggestionReportSnapshot {
        TagSuggestionReportSnapshot(
            fileID: fileID,
            suggestions: [],
            tagSet: .tagAddFixture(fileID: fileID, values: existingValues),
            contentsRead: false,
            aiUsed: false,
            networkUsed: false
        )
    }
}

extension TagSuggestionApplyReportSnapshot {
    static func tagSuggestionsApplied(
        fileID: Int64,
        suggestionID: String = "tagSuggestions-finance",
        slug: String = "finance",
        displayName _: String = "Finance"
    ) -> TagSuggestionApplyReportSnapshot {
        TagSuggestionApplyReportSnapshot(
            fileID: fileID,
            requestedCount: 1,
            appliedCount: 1,
            skippedCount: 0,
            failedCount: 0,
            itemResults: [
                TagSuggestionApplyItemResultSnapshot(
                    suggestionID: suggestionID,
                    slug: slug,
                    status: .applied,
                    error: nil
                )
            ],
            tagSet: .tagAddFixture(fileID: fileID, values: [slug]),
            undoToken: "undo-tagSuggestions",
            refreshTargets: ["tags", "change_log", "undo_actions"]
        )
    }

    static func tagSuggestionsPartialFailure(fileID: Int64) -> TagSuggestionApplyReportSnapshot {
        TagSuggestionApplyReportSnapshot(
            fileID: fileID,
            requestedCount: 2,
            appliedCount: 1,
            skippedCount: 0,
            failedCount: 1,
            itemResults: [
                TagSuggestionApplyItemResultSnapshot(
                    suggestionID: "tagSuggestions-finance",
                    slug: "finance",
                    status: .applied,
                    error: nil
                ),
                TagSuggestionApplyItemResultSnapshot(
                    suggestionID: "tagSuggestions-tax",
                    slug: "tax-review",
                    status: .failed,
                    error: "Tag relation write failed."
                )
            ],
            tagSet: .tagAddFixture(fileID: fileID, values: ["finance"]),
            undoToken: "undo-tagSuggestions-partial",
            refreshTargets: ["tags", "change_log", "undo_actions"]
        )
    }
}

extension ChangeLogEntrySnapshot {
    static func tagSuggestionsApplied() -> ChangeLogEntrySnapshot {
        ChangeLogEntrySnapshot(
            id: 223,
            fileID: 224,
            filename: "invoice_2026.pdf",
            category: "finance",
            action: "tag_suggestion_applied",
            detailJSON: "{}",
            occurredAt: 1_700_000_400
        )
    }
}

extension SearchResultPageSnapshot {
    static func tagFilterSearchPage(filters: SearchFilterStateSnapshot) -> SearchResultPageSnapshot {
        SearchResultPageSnapshot(
            query: "",
            totalCount: filters.tags.isEmpty ? 0 : 1,
            results: [],
            diagnostics: [],
            indexStatus: .ready
        )
    }
}

extension SearchFacetsSnapshot {
    static func tagFilterFacets() -> SearchFacetsSnapshot {
        SearchFacetsSnapshot(
            query: "",
            totalCount: 42,
            categories: [],
            fileKinds: [],
            tags: [
                SearchFacetCountSnapshot(
                    value: "finance",
                    label: "Finance",
                    count: 24,
                    selected: true,
                    disabled: false
                ),
                SearchFacetCountSnapshot(value: "tax", label: "Tax", count: 8, selected: true, disabled: false),
                SearchFacetCountSnapshot(value: "archive", label: "Archive", count: 0, selected: false, disabled: true)
            ],
            storageModes: [],
            dateBounds: SearchDateFacetBoundsSnapshot(
                oldestImportedAt: nil,
                newestImportedAt: nil,
                oldestModifiedAt: nil,
                newestModifiedAt: nil
            ),
            activeFilterCount: 1
        )
    }
}
