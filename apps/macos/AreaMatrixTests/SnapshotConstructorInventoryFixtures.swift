let snapshotConstructorInventories = [
    snapshotCtorInventory("CoreErrorMappingSnapshot", [("CoreErrorMappingTestDoubleSupport.swift", 1)]),
    snapshotCtorInventory("SavedSearchSnapshot", [("SavedSearchPageFixtures.swift", 1)]),
    snapshotCtorInventory("SavedSearchQuerySnapshot", [("SavedSearchPageFixtures.swift", 1)], suffix: "(request:"),
    snapshotCtorInventory("SearchFileResultSnapshot", [("SearchResultsPageFixtures.swift", 1)]),
    snapshotCtorInventory("SearchMatchSnapshot", [("SearchResultsPageFixtures.swift", 1)]),
    snapshotCtorInventory("SearchQueryRequestSnapshot", [("ConfigurationFixtures.swift", 2)]),
    snapshotCtorInventory("SearchFilterStateSnapshot", [("ConfigurationFixtures.swift", 1)]),
    snapshotCtorInventory("SyncResultSnapshot", [("ConfigurationFixtures.swift", 1)]),
    snapshotCtorInventory("DiagnosticsSnapshotSnapshot", [("ConfigurationFixtures.swift", 1)]),
    snapshotCtorInventory("FileFilterSnapshot", [("ConfigurationFixtures.swift", 1)]),
    snapshotCtorInventory("PlatformCapabilitySupportSnapshot", [("PlatformCapabilityFixtures.swift", 1)]),
    snapshotCtorInventory("PlatformCapabilitiesSnapshot", [("PlatformCapabilityFixtures.swift", 1)]),
    snapshotCtorInventory("RepoPathValidationSnapshot", [("ConfigurationFixtures.swift", 1)]),
    snapshotCtorInventory("ScanSessionSnapshot", [("ConfigurationFixtures.swift", 1)]),
    snapshotCtorInventory("ExistingRepositoryMetadataSnapshot", [("RepositorySettingsFixtures.swift", 1)]),
    snapshotCtorInventory("ClassifyResultSnapshot", [("ConfigurationFixtures.swift", 1)]),
    snapshotCtorInventory("UndoActionRecordSnapshot", [("UndoRedoActionSnapshotFixtures.swift", 1)]),
    snapshotCtorInventory("UndoActionResultSnapshot", [("UndoRedoActionSnapshotFixtures.swift", 1)]),
    snapshotCtorInventory("RedoActionRecordSnapshot", [("UndoRedoActionSnapshotFixtures.swift", 1)]),
    snapshotCtorInventory("RedoActionResultSnapshot", [("UndoRedoActionSnapshotFixtures.swift", 1)]),
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
