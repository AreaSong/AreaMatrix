@testable import AreaMatrix

extension TagRecordSnapshot {
    static func testFixture(
        value: String,
        label: String? = nil,
        fileCount: Int64 = 1,
        selected: Bool = false,
        disabled: Bool = false,
        updatedAt: Int64 = 1_700_000_300
    ) -> TagRecordSnapshot {
        TagRecordSnapshot(
            value: value,
            label: label ?? value,
            fileCount: fileCount,
            selected: selected,
            disabled: disabled,
            updatedAt: updatedAt
        )
    }
}

extension TagSetSnapshot {
    static func testFixture(
        fileID: Int64,
        fileTags: [TagRecordSnapshot] = [],
        availableTags: [TagRecordSnapshot] = [],
        recentTags: [TagRecordSnapshot] = [],
        updatedAt: Int64 = 1_700_000_300
    ) -> TagSetSnapshot {
        TagSetSnapshot(
            fileID: fileID,
            fileTags: fileTags,
            availableTags: availableTags,
            recentTags: recentTags,
            updatedAt: updatedAt
        )
    }

    static func tagAddFixture(fileID: Int64, values: [String]) -> TagSetSnapshot {
        let tags = values.map { value in
            TagRecordSnapshot.testFixture(
                value: value,
                fileCount: 1,
                selected: true,
                updatedAt: 1_700_000_300
            )
        }
        return TagSetSnapshot.testFixture(
            fileID: fileID,
            fileTags: tags,
            availableTags: tags,
            recentTags: tags,
            updatedAt: 1_700_000_300
        )
    }

    static func tagFilterRegistryFixture(fileID: Int64) -> TagSetSnapshot {
        TagSetSnapshot.testFixture(
            fileID: fileID,
            availableTags: [
                .testFixture(
                    value: "finance",
                    label: "Finance",
                    fileCount: 24,
                    updatedAt: 1_700_000_300
                ),
                .testFixture(
                    value: "legal",
                    label: "Legal",
                    fileCount: 5,
                    updatedAt: 1_700_000_301
                )
            ],
            updatedAt: 1_700_000_301
        )
    }
}

extension TagSuggestionReportSnapshot {
    static func testFixture(
        fileID: Int64,
        suggestions: [TagSuggestionSnapshot] = [],
        tagSet: TagSetSnapshot? = nil,
        contentsRead: Bool = false,
        aiUsed: Bool = false,
        networkUsed: Bool = false
    ) -> TagSuggestionReportSnapshot {
        TagSuggestionReportSnapshot(
            fileID: fileID,
            suggestions: suggestions,
            tagSet: tagSet ?? .tagAddFixture(fileID: fileID, values: []),
            contentsRead: contentsRead,
            aiUsed: aiUsed,
            networkUsed: networkUsed
        )
    }

    static func tagSuggestionsFixture(fileID: Int64, existingValues: [String] = []) -> TagSuggestionReportSnapshot {
        testFixture(
            fileID: fileID,
            suggestions: [
                .testFixture(
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
                .testFixture(
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
            tagSet: .tagAddFixture(fileID: fileID, values: existingValues)
        )
    }

    static func tagSuggestionsEmptyFixture(fileID: Int64,
                                           existingValues: [String] = []) -> TagSuggestionReportSnapshot {
        testFixture(
            fileID: fileID,
            tagSet: .tagAddFixture(fileID: fileID, values: existingValues)
        )
    }
}

extension TagSuggestionSnapshot {
    static func testFixture(
        suggestionID: String = "tagSuggestions-finance",
        slug: String = "finance",
        displayName: String = "Finance",
        reason: String = "Matched file name: invoice_2026.pdf",
        source: TagSuggestionSourceSnapshot = .fileName,
        matchStrength: TagSuggestionMatchSnapshot = .strong,
        alreadyExists: Bool = false,
        needsCreate: Bool = false,
        status: TagSuggestionStatusSnapshot = .newTag,
        selectedByDefault: Bool = true,
        disabledReason: String? = nil
    ) -> TagSuggestionSnapshot {
        TagSuggestionSnapshot(
            suggestionID: suggestionID,
            slug: slug,
            displayName: displayName,
            reason: reason,
            source: source,
            matchStrength: matchStrength,
            alreadyExists: alreadyExists,
            needsCreate: needsCreate,
            status: status,
            selectedByDefault: selectedByDefault,
            disabledReason: disabledReason
        )
    }
}

extension ApplyTagSuggestionItemSnapshot {
    static func testFixture(
        suggestionID: String,
        slug: String,
        displayName: String
    ) -> ApplyTagSuggestionItemSnapshot {
        ApplyTagSuggestionItemSnapshot(
            suggestionID: suggestionID,
            slug: slug,
            displayName: displayName
        )
    }
}

extension TagSuggestionApplyItemResultSnapshot {
    static func testFixture(
        suggestionID: String,
        slug: String,
        status: TagSuggestionApplyStatusSnapshot = .applied,
        error: String? = nil
    ) -> TagSuggestionApplyItemResultSnapshot {
        TagSuggestionApplyItemResultSnapshot(
            suggestionID: suggestionID,
            slug: slug,
            status: status,
            error: error
        )
    }
}

extension TagSuggestionApplyReportSnapshot {
    static func testFixture(
        fileID: Int64,
        requestedCount: Int64,
        appliedCount: Int64,
        skippedCount: Int64 = 0,
        failedCount: Int64 = 0,
        itemResults: [TagSuggestionApplyItemResultSnapshot] = [],
        tagSet: TagSetSnapshot? = nil,
        undoToken: String? = nil,
        refreshTargets: [String] = []
    ) -> TagSuggestionApplyReportSnapshot {
        TagSuggestionApplyReportSnapshot(
            fileID: fileID,
            requestedCount: requestedCount,
            appliedCount: appliedCount,
            skippedCount: skippedCount,
            failedCount: failedCount,
            itemResults: itemResults,
            tagSet: tagSet ?? .tagAddFixture(fileID: fileID, values: []),
            undoToken: undoToken,
            refreshTargets: refreshTargets
        )
    }

    static func tagSuggestionsApplied(
        fileID: Int64,
        suggestionID: String = "tagSuggestions-finance",
        slug: String = "finance",
        displayName _: String = "Finance"
    ) -> TagSuggestionApplyReportSnapshot {
        testFixture(
            fileID: fileID,
            requestedCount: 1,
            appliedCount: 1,
            skippedCount: 0,
            failedCount: 0,
            itemResults: [
                .testFixture(
                    suggestionID: suggestionID,
                    slug: slug
                )
            ],
            tagSet: .tagAddFixture(fileID: fileID, values: [slug]),
            undoToken: "undo-tagSuggestions",
            refreshTargets: ["tags", "change_log", "undo_actions"]
        )
    }

    static func tagSuggestionsPartialFailure(fileID: Int64) -> TagSuggestionApplyReportSnapshot {
        testFixture(
            fileID: fileID,
            requestedCount: 2,
            appliedCount: 1,
            skippedCount: 0,
            failedCount: 1,
            itemResults: [
                .testFixture(
                    suggestionID: "tagSuggestions-finance",
                    slug: "finance"
                ),
                .testFixture(
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
        ChangeLogEntrySnapshot.testFixture(
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
        .testFixture(
            query: "",
            totalCount: filters.tags.isEmpty ? 0 : 1
        )
    }
}

extension SearchFacetsSnapshot {
    static func tagFilterFacets() -> SearchFacetsSnapshot {
        SearchFacetsSnapshot.testFixture(totalCount: 42) {
            $0.tags = [
                .testFixture(
                    value: "finance",
                    label: "Finance",
                    count: 24,
                    selected: true
                ),
                .testFixture(value: "tax", label: "Tax", count: 8, selected: true),
                .testFixture(value: "archive", label: "Archive", disabled: true)
            ]
            $0.activeFilterCount = 1
        }
    }
}
