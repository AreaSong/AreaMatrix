@testable import AreaMatrix

extension CoreErrorMappingSnapshot {
    static func tagAddTagDb() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "无法更新标签",
            severity: .medium,
            suggestedAction: "请保留输入并重试标签操作。",
            recoverability: .retryable,
            rawContext: "tag-crud tag-crud-core tag-crud"
        )
    }
}

extension TagSuggestionRequestSnapshot {
    static func tagSuggestions(fileID: Int64) -> TagSuggestionRequestSnapshot {
        TagSuggestionRequestSnapshot(
            fileID: fileID,
            context: nil,
            limit: DetailTagSuggestionAction.defaultLimit
        )
    }
}

extension RepositorySidebarRowSnapshot {
    static let tagFilterRoot = RepositorySidebarRowSnapshot(node: RepositoryTreeNodeSnapshot(
        slug: "__root__",
        displayName: "Repository",
        kind: "RepositoryRoot",
        relativePath: "",
        fileCount: 0,
        depth: 0,
        children: []
    ), depth: 0)
}

extension UndoActionRecordSnapshot {
    static func tagSuggestionsApplySuggestion(token: String) -> UndoActionRecordSnapshot {
        UndoActionRecordSnapshot(
            actionID: token,
            kind: "tag_suggestion_apply",
            summary: "Applied 1 suggested tag.",
            affectedCount: 1,
            affectedFileNames: ["invoice_2026.pdf"],
            status: .pending,
            canUndo: true,
            disabledReason: nil,
            createdAt: 1_700_000_400,
            updatedAt: 1_700_000_400
        )
    }
}
