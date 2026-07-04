@testable import AreaMatrix

extension AITagBatchPageFeatureTests {
    static func aiTagMergeBridge(
        file: FileEntrySnapshot,
        unchangedFile: FileEntrySnapshot
    ) -> AITagSuggestionBatchAITagBridge {
        AITagSuggestionBatchAITagBridge(reports: [
            file.id: aiTagSuggestionAITagReport(fileID: file.id, suggestions: [
                aiTagSuggestionAITagSuggestion(
                    id: "ai-tag-merge",
                    slug: "finances",
                    confidence: 0.91,
                    selectedByDefault: false,
                    displayName: "Finances",
                    mergeAction: .mergeWithExistingTag,
                    matchedExistingSlug: "finance"
                )
            ]),
            unchangedFile.id: aiTagSuggestionAITagReport(fileID: unchangedFile.id, status: .noSuggestion)
        ])
    }

    @MainActor
    static func aiTagMergeModel(
        file: FileEntrySnapshot,
        unchangedFile: FileEntrySnapshot,
        bridge: AITagSuggestionBatchAITagBridge
    ) -> MainFileListModel {
        MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [file, unchangedFile]),
            fileLister: NoopFileLister(),
            fileDetailer: DetailTagFileDetailer(files: [file, unchangedFile]),
            aiSettingsLoader: AITagSuggestionAISettingsLoader(),
            aiTagSuggestionStore: bridge,
            aiPrivacyRules: RemotePrivacyRulesBridge(
                snapshot: .remoteProviderConfigPrivacyRules(featureScope: [.autoTags])
            ),
            errorMapper: StaticCoreErrorMapper(mapping: .tagAddTagDb())
        )
    }
}
