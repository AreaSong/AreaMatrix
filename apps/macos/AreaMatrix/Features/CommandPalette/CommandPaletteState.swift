import Foundation

enum CommandPaletteLoadState: Equatable {
    case idle
    case loading(CommandIndexContext)
    case loaded(CommandPaletteSnapshot)
    case failed(CommandIndexContext, CommandPaletteSnapshot?, CoreErrorMappingSnapshot)

    var snapshot: CommandPaletteSnapshot? {
        switch self {
        case let .loaded(snapshot), let .failed(_, snapshot?, _):
            snapshot
        case .idle, .loading, .failed:
            nil
        }
    }

    var errorMapping: CoreErrorMappingSnapshot? {
        guard case let .failed(_, _, mapping) = self else { return nil }
        return mapping
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

struct CommandPaletteSnapshot: Equatable {
    var sections: [CommandPaletteSectionSnapshot]
    var generatedAt: Int64

    var isEmpty: Bool {
        sections.allSatisfy(\.targets.isEmpty)
    }
}

struct CommandPaletteSectionSnapshot: Equatable, Identifiable {
    var title: String
    var targets: [CommandTargetSnapshot]

    init(title: String, targets: [CommandTarget]) {
        self.title = title
        self.targets = targets.map(CommandTargetSnapshot.init(coreTarget:))
    }

    init(title: String, targets: [CommandTargetSnapshot]) {
        self.title = title
        self.targets = targets
    }

    var id: String {
        title
    }
}

struct CommandTargetSnapshot: Equatable, Identifiable {
    var id: String
    var title: String
    var subtitle: String?
    var group: CommandTargetGroupSnapshot
    var kind: CommandTargetKindSnapshot
    var action: CommandTargetActionSnapshot
    var route: String?
    var shortcut: String?
    var disabled: Bool
    var disabledReason: String?
    var requiresConfirmation: Bool
    var fileID: Int64?
    var savedSearchID: Int64?

    init(coreTarget: CommandTarget) {
        id = coreTarget.id
        title = CommandTargetPresentation.title(for: coreTarget)
        subtitle = CommandTargetPresentation.subtitle(for: coreTarget)
        group = CommandTargetGroupSnapshot(coreGroup: coreTarget.group)
        kind = CommandTargetKindSnapshot(coreKind: coreTarget.kind)
        action = CommandTargetActionSnapshot(coreAction: coreTarget.action)
        route = coreTarget.route
        shortcut = coreTarget.shortcut
        disabled = coreTarget.disabled
        disabledReason = CommandTargetPresentation.disabledReason(for: coreTarget)
        requiresConfirmation = coreTarget.requiresConfirmation
        fileID = coreTarget.fileId
        savedSearchID = coreTarget.savedSearchId
    }

    init(
        id: String,
        title: String,
        subtitle: String?,
        group: CommandTargetGroupSnapshot,
        kind: CommandTargetKindSnapshot,
        action: CommandTargetActionSnapshot,
        route: String?,
        shortcut: String?,
        disabled: Bool,
        disabledReason: String?,
        requiresConfirmation: Bool,
        fileID: Int64?,
        savedSearchID: Int64?
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.group = group
        self.kind = kind
        self.action = action
        self.route = route
        self.shortcut = shortcut
        self.disabled = disabled
        self.disabledReason = disabledReason
        self.requiresConfirmation = requiresConfirmation
        self.fileID = fileID
        self.savedSearchID = savedSearchID
    }
}

enum CommandPaletteTargetRoute: Equatable {
    case importFiles
    case settings
    case beginSearch
    case batchAddTags
    case batchChangeCategory
    case batchDelete
    case batchRename
    case classifierRuleEditor
    case runSmartList(Int64)
    case focusFile(Int64)
    case openRepository
    case help
    case linkedPage(CommandPaletteLinkedPageRoute)
    case unsupported
}

enum CommandTargetGroupSnapshot: String, Equatable {
    case commands = "Commands"
    case navigation = "Navigation"
    case currentSelection = "Current Selection"
    case recent = "Recent"
    case smartLists = "Smart Lists"
    case fileCandidates = "File Candidates"

    var displayName: String {
        switch self {
        case .commands: L10n.string("Commands")
        case .navigation: L10n.string("Navigation")
        case .currentSelection: L10n.string("Current Selection")
        case .recent: L10n.string("Recent")
        case .smartLists: L10n.string("Smart Lists")
        case .fileCandidates: L10n.string("File Candidates")
        }
    }

    init(coreGroup: CommandTargetGroup) {
        switch coreGroup {
        case .commands:
            self = .commands
        case .navigation:
            self = .navigation
        case .currentSelection:
            self = .currentSelection
        case .recent:
            self = .recent
        case .smartLists:
            self = .smartLists
        case .fileCandidates:
            self = .fileCandidates
        }
    }
}

enum CommandTargetKindSnapshot: String, Equatable {
    case command = "Command"
    case navigation = "Navigation"
    case smartList = "Smart List"
    case fileCandidate = "File Candidate"
    case recentCommand = "Recent Command"

    init(coreKind: CommandTargetKind) {
        switch coreKind {
        case .command:
            self = .command
        case .navigation:
            self = .navigation
        case .smartList:
            self = .smartList
        case .fileCandidate:
            self = .fileCandidate
        case .recentCommand:
            self = .recentCommand
        }
    }
}

enum CommandTargetActionSnapshot: String, Equatable {
    case navigate = "Navigate"
    case openSheet = "Open Sheet"
    case openConfirmation = "Open Confirmation"
    case runSmartList = "Run Smart List"
    case focusFile = "Focus File"
    case openSearch = "Open Search"
    case lowRiskAction = "Low Risk Action"

    var displayName: String {
        switch self {
        case .navigate: L10n.string("Navigate")
        case .openSheet: L10n.string("Open Sheet")
        case .openConfirmation: L10n.string("Open Confirmation")
        case .runSmartList: L10n.string("Run Smart List")
        case .focusFile: L10n.string("Focus File")
        case .openSearch: L10n.string("Open Search")
        case .lowRiskAction: L10n.string("Low Risk Action")
        }
    }

    init(coreAction: CommandTargetAction) {
        switch coreAction {
        case .navigate:
            self = .navigate
        case .openSheet:
            self = .openSheet
        case .openConfirmation:
            self = .openConfirmation
        case .runSmartList:
            self = .runSmartList
        case .focusFile:
            self = .focusFile
        case .openSearch:
            self = .openSearch
        case .lowRiskAction:
            self = .lowRiskAction
        }
    }
}

extension CommandTargetSnapshot {
    var isExecutable: Bool {
        executionRoute != .unsupported && (!disabled || usesDynamicRedoAvailability)
    }

    var confirmationLabel: String? {
        requiresConfirmation ? L10n.string("Requires confirmation") : nil
    }

    var effectiveDisabledReason: String? {
        isExecutable ? nil : disabledReason
    }

    var executionRoute: CommandPaletteTargetRoute {
        switch action {
        case .openSheet:
            return openSheetRoute
        case .openConfirmation:
            return confirmationRoute
        case .navigate:
            return navigationRoute
        case .runSmartList:
            guard let savedSearchID else { return .unsupported }
            return .runSmartList(savedSearchID)
        case .focusFile:
            guard let fileID else { return .unsupported }
            return .focusFile(fileID)
        case .openSearch:
            return .beginSearch
        case .lowRiskAction:
            return .unsupported
        }
    }

    private var openSheetRoute: CommandPaletteTargetRoute {
        switch route {
        case "import":
            .importFiles
        case "batch-add-tags":
            .batchAddTags
        default:
            linkedPageRoute ?? .unsupported
        }
    }

    private var confirmationRoute: CommandPaletteTargetRoute {
        switch route {
        case "batch-change-category":
            .batchChangeCategory
        case "batch-delete":
            .batchDelete
        case "batch-rename":
            .batchRename
        default:
            linkedPageRoute ?? .unsupported
        }
    }

    private var navigationRoute: CommandPaletteTargetRoute {
        switch route {
        case "settings":
            .settings
        case "openRepository":
            .openRepository
        case "help":
            .help
        case "classifier-rule-editor":
            .classifierRuleEditor
        case "search":
            .beginSearch
        default:
            linkedPageRoute ?? .unsupported
        }
    }

    private var linkedPageRoute: CommandPaletteTargetRoute? {
        guard let route else { return nil }
        switch route {
        case CommandPaletteLinkedPageRoute.classifierImpactPreview.pageID:
            return .linkedPage(.classifierImpactPreview)
        case CommandPaletteLinkedPageRoute.importConflictBatch.pageID:
            return .linkedPage(.importConflictBatch)
        case CommandPaletteLinkedPageRoute.redo.pageID:
            return .linkedPage(.redo)
        case CommandPaletteLinkedPageRoute.tagSuggestions.pageID:
            return .linkedPage(.tagSuggestions)
        default:
            return nil
        }
    }

    private var usesDynamicRedoAvailability: Bool {
        if case .linkedPage(.redo) = executionRoute { return true }
        return false
    }
}

enum CommandPaletteSmartListRouting {
    static func savedSearch(savedSearchID: Int64, in savedSearches: [SavedSearchSnapshot]) -> SavedSearchSnapshot? {
        savedSearches.first { $0.id == savedSearchID }
    }
}

extension CommandIndexContext {
    static func commandPalette(
        query: String,
        selectedFileIDs: Set<Int64>,
        currentPath: String?,
        includeFileCandidates: Bool = true
    ) -> CommandIndexContext {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return CommandIndexContext(
            query: trimmed.isEmpty ? nil : trimmed,
            selectedFileIds: selectedFileIDs.sorted(),
            currentPath: currentPath,
            includeFileCandidates: includeFileCandidates
        )
    }
}

extension CommandPaletteSnapshot {
    init(coreIndex: CommandIndex) {
        generatedAt = coreIndex.generatedAt
        sections = [
            CommandPaletteSectionSnapshot(
                title: CommandTargetGroupSnapshot.commands.displayName,
                targets: coreIndex.commands
            ),
            CommandPaletteSectionSnapshot(
                title: CommandTargetGroupSnapshot.navigation.displayName,
                targets: coreIndex.navigationTargets
            ),
            CommandPaletteSectionSnapshot(
                title: CommandTargetGroupSnapshot.currentSelection.displayName,
                targets: coreIndex.currentSelectionTargets
            ),
            CommandPaletteSectionSnapshot(
                title: CommandTargetGroupSnapshot.recent.displayName,
                targets: coreIndex.recentTargets
            ),
            CommandPaletteSectionSnapshot(
                title: CommandTargetGroupSnapshot.smartLists.displayName,
                targets: coreIndex.smartLists
            ),
            CommandPaletteSectionSnapshot(
                title: CommandTargetGroupSnapshot.fileCandidates.displayName,
                targets: coreIndex.fileCandidates
            )
        ]
    }
}

@MainActor
extension MainFileListModel {
    func loadCommandIndex(
        query: String,
        selectedFileIDs: Set<Int64>,
        currentPath: String?
    ) async {
        let context = CommandIndexContext.commandPalette(
            query: query,
            selectedFileIDs: selectedFileIDs,
            currentPath: currentPath
        )
        let availableCommands = commandPaletteState.snapshot
        commandPaletteState = .loading(context)
        do {
            let index = try await commandIndexer.listCommandTargets(repoPath: repoPath, context: context)
            commandPaletteState = .loaded(CommandPaletteSnapshot(coreIndex: index))
        } catch {
            let mappedError = await mapCoreError(error)
            commandPaletteState = .failed(
                context,
                availableCommands ?? .commandRegistryRecovery(query: context.query),
                mappedError
            )
        }
    }

    func clearCommandPaletteState() {
        commandPaletteState = .idle
    }
}
