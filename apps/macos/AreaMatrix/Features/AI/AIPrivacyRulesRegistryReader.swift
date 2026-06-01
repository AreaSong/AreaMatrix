import Foundation

protocol AIPrivacyRuleRegistryReading: Sendable {
    func loadRegistry(repoPath: String) async throws -> AIPrivacyRuleRegistrySnapshot
}

struct CoreAIPrivacyRuleRegistryReader: AIPrivacyRuleRegistryReading {
    private let classifierReader: any CoreClassifierRuleEditing
    private let facetReader: any CoreSearchFiltering

    init(
        classifierReader: any CoreClassifierRuleEditing = CoreBridge(),
        facetReader: any CoreSearchFiltering = CoreBridge()
    ) {
        self.classifierReader = classifierReader
        self.facetReader = facetReader
    }

    func loadRegistry(repoPath: String) async throws -> AIPrivacyRuleRegistrySnapshot {
        async let classifier = classifierReader.listClassifierRules(repoPath: repoPath)
        async let facets = facetReader.listFilterFacets(
            repoPath: repoPath,
            request: SearchFacetRequestSnapshot(
                query: "",
                scope: .all,
                currentPath: nil,
                category: nil,
                filters: .empty
            )
        )
        let (classifierSnapshot, facetSnapshot) = try await (classifier, facets)
        return AIPrivacyRuleRegistrySnapshot(
            categories: classifierSnapshot.rules.map(\.slug).sorted(),
            tags: facetSnapshot.tags.map(\.value).sorted()
        )
    }
}

