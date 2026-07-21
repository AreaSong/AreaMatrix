@testable import AreaMatrix

extension [DetailMetaMetadataRow] {
    func value(for label: String) -> String? {
        first { $0.label == label }?.value
    }
}

@MainActor
func assertMainRepositoryDetailFileActionMenu(
    for detail: FileEntrySnapshot,
    disabledReason: MainFileWriteActionDisabledReason? = nil,
    contains expectedFragments: [String],
    file sourceFile: StaticString = #filePath,
    line: UInt = #line
) {
    let menu = MainRepositoryDetailFileActionMenu(
        detail: detail,
        disabledReason: disabledReason,
        missingFileRelinkState: .idle,
        onLocateMissingFile: { _ in },
        onBeginRenameFile: { _ in },
        onBeginChangeCategoryFile: { _ in },
        onBeginClassifierCorrectionFile: { _ in },
        onBeginAIClassificationSuggestionFile: { _ in },
        onBeginDeleteFile: { _ in },
        onBeginICloudConflictResolution: { _ in },
        onBeginSyncConflictReview: { _ in }
    )
    assertTestMirrorDescription(
        of: menu.body,
        contains: expectedFragments,
        maxDepth: 8,
        file: sourceFile,
        line: line
    )
}
