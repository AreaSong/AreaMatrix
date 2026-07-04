@testable import AreaMatrix

@MainActor
func aiCategorySuggestionSuggestionModel(
    request: AIClassificationSuggestionRequestState,
    bridge: AICategorySuggestionSuggestionBridge,
    fallbackBridge: AICategorySuggestionFallbackBridge = AICategorySuggestionFallbackBridge()
) -> AIClassificationSuggestionPanelModel {
    AIClassificationSuggestionPanelModel(
        repoPath: "/tmp/repo",
        request: request,
        suggester: bridge,
        fallbackReader: fallbackBridge,
        errorMapper: aiCategorySuggestionErrorMapper()
    )
}

func aiCategorySuggestionErrorMapper() -> StaticCoreErrorMapper {
    StaticCoreErrorMapper(mapping: CoreErrorMappingSnapshot(
        kind: .config,
        userMessage: "Mapped ai-classification-suggestion core error",
        severity: .medium,
        suggestedAction: "Open AI settings",
        recoverability: .userActionRequired,
        rawContext: "ai-category-suggestion ai-classification-suggestion"
    ))
}
