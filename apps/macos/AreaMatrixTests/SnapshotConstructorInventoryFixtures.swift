let snapshotConstructorInventories = [
    snapshotCtorInventory("CoreErrorMappingSnapshot", [("CoreErrorMappingTestDoubleSupport.swift", 2)]),
    snapshotCtorInventory("SavedSearchSnapshot", [("SavedSearchPageFixtures.swift", 1)]),
    snapshotCtorInventory("SavedSearchQuerySnapshot", [("SavedSearchPageFixtures.swift", 1)], suffix: "(request:"),
    snapshotCtorInventory("CreateSavedSearchRequestSnapshot", [("SavedSearchPageFixtures.swift", 1)]),
    snapshotCtorInventory("SearchFileResultSnapshot", [("SearchResultsPageFixtures.swift", 1)]),
    snapshotCtorInventory("SearchMatchSnapshot", [("SearchResultsPageFixtures.swift", 1)]),
    snapshotCtorInventory("SemanticSearchMatchSnapshot", [("SemanticSearchPageFixtures.swift", 1)]),
    snapshotCtorInventory("SemanticNormalSearchMatchSnapshot", [("SemanticSearchPageFixtures.swift", 1)]),
    snapshotCtorInventory("SemanticIndexBuildReportSnapshot", [("SemanticSearchPageFixtures.swift", 1)]),
    snapshotCtorInventory("SearchDateFacetBoundsSnapshot", [("SearchFiltersFixtures.swift", 1)]),
    snapshotCtorInventory("SearchFacetCountSnapshot", [("SearchFiltersFixtures.swift", 1)]),
    snapshotCtorInventory("SearchFacetsSnapshot", [("SearchFiltersFixtures.swift", 1)]),
    snapshotCtorInventory("SearchQueryDiagnosticSnapshot", [
        ("SearchQueryDiagnosticFixtures.swift", 1),
        ("ValidatePathErrorMappingSmokeTests.swift", 1)
    ]),
    snapshotCtorInventory("SearchQueryRequestSnapshot", [("ConfigurationFixtures.swift", 2)]),
    snapshotCtorInventory("SearchFilterStateSnapshot", [("ConfigurationFixtures.swift", 1)]),
    snapshotCtorInventory("TagRecordSnapshot", [("CoreTagSuggestionFixtures.swift", 1)]),
    snapshotCtorInventory("TagSetSnapshot", [("CoreTagSuggestionFixtures.swift", 1)]),
    snapshotCtorInventory("TagSuggestionSnapshot", [("CoreTagSuggestionFixtures.swift", 1)]),
    snapshotCtorInventory("TagSuggestionReportSnapshot", [("CoreTagSuggestionFixtures.swift", 1)]),
    snapshotCtorInventory("ApplyTagSuggestionItemSnapshot", [("CoreTagSuggestionFixtures.swift", 1)]),
    snapshotCtorInventory("TagSuggestionApplyItemResultSnapshot", [("CoreTagSuggestionFixtures.swift", 1)]),
    snapshotCtorInventory("TagSuggestionApplyReportSnapshot", [("CoreTagSuggestionFixtures.swift", 1)]),
    snapshotCtorInventory("BatchMutationItemResultSnapshot", [("BatchAddTagsFixtures.swift", 1)]),
    snapshotCtorInventory("BatchMutationReportSnapshot", [("BatchAddTagsFixtures.swift", 1)]),
    snapshotCtorInventory("ImportConflictBatchPreviewReportSnapshot", [("ImportBatchPrecheckFixtures.swift", 1)]),
    snapshotCtorInventory("ImportConflictBatchPreviewItemSnapshot", [("ImportBatchPrecheckFixtures.swift", 1)]),
    snapshotCtorInventory("ImportConflictBatchApplyRequestSnapshot", [("ImportBatchPrecheckFixtures.swift", 1)]),
    snapshotCtorInventory("ImportConflictBatchApplyReportSnapshot", [("ImportBatchPrecheckFixtures.swift", 1)]),
    snapshotCtorInventory("ImportConflictBatchItemResultSnapshot", [("ImportBatchPrecheckFixtures.swift", 1)]),
    snapshotCtorInventory("ImportBatchSessionSnapshot", [("ImportProgressFixtures.swift", 1)]),
    snapshotCtorInventory("AISettingsConfigSnapshot", [("AISettingsFixtures.swift", 1)]),
    snapshotCtorInventory("AISettingsFeatureConfigSnapshot", [("AISettingsFixtures.swift", 1)]),
    snapshotCtorInventory("AISettingsSnapshot", [("AISettingsFixtures.swift", 1)]),
    snapshotCtorInventory("AIPrivacyProviderScopeSnapshot", [("RemotePrivacyRulesFixtures.swift", 1)]),
    snapshotCtorInventory("AIPrivacyRulesSnapshot", [("RemotePrivacyRulesFixtures.swift", 1)]),
    snapshotCtorInventory("AIPrivacyFieldStateSnapshot", [("RemotePrivacyRulesFixtures.swift", 1)]),
    snapshotCtorInventory("AIPrivacyRuleRegistrySnapshot", [("RemotePrivacyRulesFixtures.swift", 1)]),
    snapshotCtorInventory("AppRepoConfigSnapshot", [("RepositoryConfigFixtures.swift", 1)]),
    snapshotCtorInventory("IntegrationsICloudSnapshot", [("ConfigurationFixtures.swift", 1)]),
    snapshotCtorInventory("ICloudConflictVersionSnapshot", [("ICloudConflictMinimalFixtures.swift", 1)]),
    snapshotCtorInventory("SyncConflictResolutionRequestSnapshot", [("SyncConflictReviewResolutionFixtures.swift", 1)]),
    snapshotCtorInventory("MoveToCategoryPreviewSnapshot", [("ChangeCategoryPageFixtures.swift", 1)]),
    snapshotCtorInventory("BatchCategoryChangeReportSnapshot", [("BatchChangeCategoryFixtures.swift", 1)]),
    snapshotCtorInventory("ClassifierRuleRecordSnapshot", [("ClassifierSettingsFixtures.swift", 1)]),
    snapshotCtorInventory("ClassifierRuleDraftSnapshot", [("ClassifierSettingsFixtures.swift", 1)]),
    snapshotCtorInventory("ClassifierRuleSnapshot", [("ClassifierSettingsFixtures.swift", 1)]),
    snapshotCtorInventory("ClassifierCorrectionResultSnapshot", [("ChangeCategoryPageFixtures.swift", 1)]),
    snapshotCtorInventory("CommandPaletteSnapshot", [("CommandPaletteCommandFixtures.swift", 2)]),
    snapshotCtorInventory("CommandTargetSnapshot", [("CommandPaletteCommandFixtures.swift", 2)]),
    snapshotCtorInventory("SyncResultSnapshot", [("ConfigurationFixtures.swift", 1)]),
    snapshotCtorInventory("DiagnosticsSnapshotSnapshot", [("ConfigurationFixtures.swift", 1)]),
    snapshotCtorInventory("FileFilterSnapshot", [("ConfigurationFixtures.swift", 1)]),
    snapshotCtorInventory("ChangeLogEntrySnapshot", [("ConfigurationFixtures.swift", 1)]),
    snapshotCtorInventory("PlatformCapabilitySupportSnapshot", [("PlatformCapabilityFixtures.swift", 1)]),
    snapshotCtorInventory("PlatformCapabilitiesSnapshot", [("PlatformCapabilityFixtures.swift", 1)]),
    snapshotCtorInventory("RepoPathValidationSnapshot", [("ConfigurationFixtures.swift", 1)]),
    snapshotCtorInventory("ScanSessionSnapshot", [("ConfigurationFixtures.swift", 1)]),
    snapshotCtorInventory("RepositorySidebarRowSnapshot", [("ConfigurationFixtures.swift", 1)]),
    snapshotCtorInventory("ExistingRepositoryMetadataSnapshot", [("RepositorySettingsFixtures.swift", 1)]),
    snapshotCtorInventory("RepairOptionsSnapshot", [("DatabaseRepairConfirmPageFixtures.swift", 1)]),
    snapshotCtorInventory("RepairReportSnapshot", [("DatabaseRepairConfirmPageFixtures.swift", 1)]),
    snapshotCtorInventory("ClassifyResultSnapshot", [("ConfigurationFixtures.swift", 1)]),
    snapshotCtorInventory("UndoActionRecordSnapshot", [("UndoRedoActionSnapshotFixtures.swift", 1)]),
    snapshotCtorInventory("UndoActionResultSnapshot", [("UndoRedoActionSnapshotFixtures.swift", 1)]),
    snapshotCtorInventory("RedoActionRecordSnapshot", [("UndoRedoActionSnapshotFixtures.swift", 1)]),
    snapshotCtorInventory("RedoActionResultSnapshot", [("UndoRedoActionSnapshotFixtures.swift", 1)]),
    snapshotCtorInventory("BatchRenameRuleSnapshot", [("RenameFilePageFixtures.swift", 1)]),
    snapshotCtorInventory("UndoHistorySnapshot", [("UndoRedoActionSnapshotFixtures.swift", 1)])
]

func exactTermCount(in contents: String, term: String) -> Int {
    var count = 0
    var searchStart = contents.startIndex

    while let range = contents.range(of: term, range: searchStart ..< contents.endIndex) {
        let isExactTypeName = range.lowerBound == contents.startIndex ||
            !isIdentifierCharacter(contents[contents.index(before: range.lowerBound)])

        if isExactTypeName {
            count += 1
        }

        searchStart = range.upperBound
    }

    return count
}

private func snapshotCtorInventory(
    _ typeName: String,
    _ files: [(String, Int)],
    suffix: String = "("
) -> (term: String, inventory: [String]) {
    let term = typeName + suffix
    let inventory = files.map { fileName, count in
        "\(fileName):\(term):\(count)"
    }
    return (term, inventory)
}

private func isIdentifierCharacter(_ character: Character) -> Bool {
    character == "_" || character.isLetter || character.isNumber
}
