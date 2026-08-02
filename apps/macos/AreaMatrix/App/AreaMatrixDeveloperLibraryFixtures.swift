import Foundation

#if DEBUG
enum DeveloperLibraryScenarioFixture {
    static let repoPath = DeveloperFileActionScenarioFixture.repoPath
    static let files = DeveloperFileActionScenarioFixture.selectedFiles
    static let primaryFile = DeveloperFileActionScenarioFixture.primaryFile

    static var changeLogEntries: [ChangeLogEntrySnapshot] {
        [
            ChangeLogEntrySnapshot(
                id: 701,
                fileID: primaryFile.id,
                filename: primaryFile.currentName,
                category: primaryFile.category,
                action: "imported",
                detailJSON: #"{"mode":"Copied","source":"quarterly-report.pdf"}"#,
                occurredAt: DeveloperFileActionScenarioFixture.timestamp - 3600
            ),
            ChangeLogEntrySnapshot(
                id: 702,
                fileID: primaryFile.id,
                filename: primaryFile.currentName,
                category: primaryFile.category,
                action: "edited_note",
                detailJSON: #"{"revision":2}"#,
                occurredAt: DeveloperFileActionScenarioFixture.timestamp
            )
        ]
    }

    static var commandPaletteSnapshot: CommandPaletteSnapshot {
        CommandPaletteSnapshot(
            sections: [
                CommandPaletteSectionSnapshot(
                    title: L10n.string("Navigation"),
                    targets: [
                        commandTarget(
                            id: "developer-settings",
                            title: L10n.string("Settings"),
                            kind: .navigation,
                            action: .navigate,
                            route: "settings",
                            shortcut: "Command-,"
                        ),
                        commandTarget(
                            id: "developer-search",
                            title: L10n.string("Search files"),
                            kind: .navigation,
                            action: .navigate,
                            route: "search",
                            shortcut: "Command-F"
                        )
                    ]
                ),
                CommandPaletteSectionSnapshot(
                    title: L10n.string("Commands"),
                    targets: [
                        commandTarget(
                            id: "developer-import",
                            title: L10n.string("Import..."),
                            kind: .command,
                            action: .openSheet,
                            route: "import"
                        ),
                        commandTarget(
                            id: "developer-batch-delete",
                            title: L10n.string("Delete"),
                            kind: .command,
                            action: .openConfirmation,
                            route: "batch-delete",
                            requiresConfirmation: true
                        )
                    ]
                )
            ],
            generatedAt: DeveloperFileActionScenarioFixture.timestamp
        )
    }

    static var tagActions: MainRepositoryDetailPaneTagActions {
        MainRepositoryDetailPaneTagActions(
            aiSuggestionState: .idle,
            aiBatchSuggestionState: .idle,
            onLoadTags: {},
            onRetryTags: {},
            onAddTag: { _ in },
            onRemoveTag: { _ in },
            onLoadSuggestions: {},
            onRetrySuggestions: {},
            onToggleSuggestion: { _ in },
            onSelectAllSuggestions: {},
            onClearSuggestions: {},
            onStartEditingSuggestions: {},
            onCancelEditingSuggestions: {},
            onEditSuggestionDisplayName: { _, _ in },
            onEditSuggestionSlug: { _, _ in },
            onRegenerateSuggestionSlug: { _ in },
            onApplySuggestions: {},
            onApplyEditedSuggestions: {},
            onRetryFailedSuggestions: {},
            onLoadAISuggestions: {},
            onRetryAISuggestions: {},
            onToggleAISuggestion: { _ in },
            onApplySingleAISuggestion: { _ in },
            onSelectHighConfidenceAISuggestions: {},
            onClearAISuggestions: {},
            onStartEditingAISuggestions: {},
            onCancelEditingAISuggestions: {},
            onEditAISuggestionDisplayName: { _, _ in },
            onEditAISuggestionSlug: { _, _ in },
            onRegenerateAISuggestionSlug: { _ in },
            onApplyAISuggestions: {},
            onApplyEditedAISuggestions: {},
            onRetryFailedAISuggestions: {},
            aiBatchActions: .noop,
            onOpenAISettings: {},
            onSuggestionPresentationConsumed: { _ in },
            onUndoTagChange: {},
            onDismissTagUndoToast: {},
            onBatchTagUndoStateChange: { _ in }
        )
    }

    static var note: String {
        DeveloperFileActionScenarioFixture.userContent(
            "Review the quarterly assumptions before the finance meeting."
        )
    }

    private static func commandTarget(
        id: String,
        title: String,
        kind: CommandTargetKindSnapshot,
        action: CommandTargetActionSnapshot,
        route: String,
        shortcut: String? = nil,
        requiresConfirmation: Bool = false
    ) -> CommandTargetSnapshot {
        CommandTargetSnapshot(
            id: id,
            title: title,
            subtitle: nil,
            group: kind == .navigation ? .navigation : .commands,
            kind: kind,
            action: action,
            route: route,
            shortcut: shortcut,
            disabled: false,
            disabledReason: nil,
            requiresConfirmation: requiresConfirmation,
            fileID: nil,
            savedSearchID: nil
        )
    }
}

actor DeveloperDetailNoteStore: CoreNoteReadingWriting {
    private var note = DeveloperLibraryScenarioFixture.note

    func readNote(repoPath _: String, fileID _: Int64) async throws -> String? {
        note
    }

    func writeNote(repoPath _: String, fileID _: Int64, contentMarkdown: String) async throws {
        note = contentMarkdown
    }
}
#endif
