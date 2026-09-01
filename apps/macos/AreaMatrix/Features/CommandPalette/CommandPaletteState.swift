import Combine
import Foundation

@MainActor
final class CommandPaletteModel: ObservableObject {
    @Published var query = ""
    @Published var state = CommandPaletteLoadState.idle
    @Published var focusRoutingState = CommandPaletteFocusRoutingState()
    @Published var importConflictBatchRelayState = ImportConflictBatchRelayState()

    private let repoPath: String
    private let commandIndexer: any CoreCommandIndexing
    private let errorMapper: any CoreErrorMapping

    init(
        repoPath: String,
        commandIndexer: any CoreCommandIndexing,
        errorMapper: any CoreErrorMapping
    ) {
        self.repoPath = repoPath
        self.commandIndexer = commandIndexer
        self.errorMapper = errorMapper
    }

    var snapshot: CommandPaletteSnapshot? {
        state.snapshot
    }

    func load(query: String, selectedFileIDs: Set<Int64>, currentPath: String?) async {
        let context = CommandIndexRequestSnapshot.commandPalette(
            query: query,
            selectedFileIDs: selectedFileIDs,
            currentPath: currentPath
        )
        let availableCommands = state.snapshot
        state = .loading(context)
        do {
            let index = try await commandIndexer.listCommandTargets(repoPath: repoPath, context: context)
            state = .loaded(CommandPaletteSnapshot(coreIndex: index))
        } catch {
            let mappedError = await errorMapper.mapError(error)
            state = .failed(
                context,
                availableCommands ?? .commandRegistryRecovery(query: context.query),
                mappedError
            )
        }
    }

    func clear() {
        state = .idle
    }

    func showNoRepositoryCommands() {
        state = .loaded(.noRepositoryCommands())
    }
}

enum CommandPaletteLoadState: Equatable {
    case idle
    case loading(CommandIndexRequestSnapshot)
    case loaded(CommandPaletteSnapshot)
    case failed(CommandIndexRequestSnapshot, CommandPaletteSnapshot?, CoreErrorMappingSnapshot)

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

    init(title: String, targets: [CoreCommandTargetSnapshot]) {
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

    init(coreTarget: CoreCommandTargetSnapshot) {
        id = coreTarget.id
        title = CommandTargetPresentation.title(for: coreTarget)
        subtitle = CommandTargetPresentation.subtitle(for: coreTarget)
        group = coreTarget.group
        kind = coreTarget.kind
        action = coreTarget.action
        route = coreTarget.route
        shortcut = coreTarget.shortcut
        disabled = coreTarget.disabled
        disabledReason = CommandTargetPresentation.disabledReason(for: coreTarget)
        requiresConfirmation = coreTarget.requiresConfirmation
        fileID = coreTarget.fileID
        savedSearchID = coreTarget.savedSearchID
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

extension CommandTargetGroupSnapshot {
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
}

extension CommandTargetActionSnapshot {
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

extension CommandIndexRequestSnapshot {
    static func commandPalette(
        query: String,
        selectedFileIDs: Set<Int64>,
        currentPath: String?,
        includeFileCandidates: Bool = true
    ) -> CommandIndexRequestSnapshot {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return CommandIndexRequestSnapshot(
            query: trimmed.isEmpty ? nil : trimmed,
            selectedFileIDs: selectedFileIDs.sorted(),
            currentPath: currentPath,
            includeFileCandidates: includeFileCandidates
        )
    }
}

extension CommandPaletteSnapshot {
    init(coreIndex: CoreCommandIndexSnapshot) {
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
