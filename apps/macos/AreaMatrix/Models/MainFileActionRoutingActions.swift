import Foundation

extension MainFileListModel {
    func beginRename(fileID: Int64? = nil) {
        guard let fileID = fileID ?? selection.singleFileID,
              writeActionDisabledReason(fileID: fileID) == nil else { return }
        renameState = .idle
        pendingActionDestination = .rename(fileID: fileID)
    }

    func beginChangeCategory(fileID: Int64? = nil) {
        guard let fileID = fileID ?? selection.singleFileID,
              writeActionDisabledReason(fileID: fileID) == nil else { return }
        changeCategoryState = .idle
        pendingActionDestination = .changeCategory(fileID: fileID)
    }

    func beginRenameFromChangeCategory(fileID: Int64, targetCategory: String) {
        guard pendingActionDestination?.isChangeCategory(fileID: fileID) == true,
              writeActionDisabledReason(fileID: fileID) == nil,
              !changeCategoryState.isMoving(fileID: fileID) else { return }
        renameState = .returningToChangeCategory(fileID: fileID, targetCategory: targetCategory)
        pendingActionDestination = .rename(fileID: fileID)
    }

    func beginDelete(fileID: Int64? = nil) {
        guard let fileID = fileID ?? selection.singleFileID,
              writeActionDisabledReason(fileID: fileID) == nil else { return }
        pendingActionDestination = .delete(fileID: fileID)
    }

    func beginICloudConflictResolution(fileID: Int64? = nil) {
        guard let fileID = fileID ?? selection.singleFileID,
              let file = file(for: fileID),
              file.hasICloudConflictCopySignal,
              writeActionDisabledReason(fileID: fileID) == nil else { return }
        iCloudConflictResolutionState = .idle
        pendingActionDestination = .iCloudConflict(fileID: fileID)
    }

    func openClassifierRuleEditorForBatchCategory(context: BatchChangeCategoryNewCategoryReturnContext) {
        pendingSearchDestination = .classifierRuleEditor(context: context)
    }

    func applyICloudConflictResolution(
        fileID: Int64,
        strategy: ICloudConflictResolutionStrategy,
        originalPath: String?,
        conflictedCopyPath: String?
    ) async {
        guard pendingActionDestination == .iCloudConflict(fileID: fileID) else { return }
        guard !iCloudConflictResolutionState.isApplying,
              writeActionDisabledReason(fileID: fileID) == nil else { return }

        if let blocker = iCloudConflictResolver.iCloudConflictResolutionCapability.blocker {
            let mapping = await mapCoreError(blocker.coreError)
            iCloudConflictResolutionState = .failed(fileID: fileID, strategy: strategy, mapping)
            return
        }

        iCloudConflictResolutionState = .applying(fileID: fileID, strategy: strategy)
        clearDiagnosticsState()
        do {
            let result = try await iCloudConflictResolver.resolveICloudConflict(ICloudConflictResolutionRequest(
                repoPath: repoPath,
                fileID: fileID,
                strategy: strategy,
                originalPath: originalPath,
                conflictedCopyPath: conflictedCopyPath
            ))
            try validateICloudConflictResolution(result, fileID: fileID)
            await refreshAfterICloudConflictResolution(fileID: result.focusFileID ?? fileID, strategy: strategy)
        } catch {
            let mapping = await mapCoreError(error)
            guard pendingActionDestination == .iCloudConflict(fileID: fileID) else { return }
            iCloudConflictResolutionState = .failed(fileID: fileID, strategy: strategy, mapping)
        }
    }

    func applyKeepBothICloudConflict(fileID: Int64) async {
        let versions = iCloudConflictVersions(for: fileID)
        await applyICloudConflictResolution(
            fileID: fileID,
            strategy: .keepBoth,
            originalPath: versions.original,
            conflictedCopyPath: versions.conflictedCopy
        )
    }

    func iCloudConflictVersions(for fileID: Int64) -> (original: String?, conflictedCopy: String?) {
        let file = file(for: fileID)
        return (
            ICloudConflictVersionSnapshot.originalCandidate(repoPath: repoPath, file: file).path,
            ICloudConflictVersionSnapshot.conflictedCandidate(repoPath: repoPath, file: file).path
        )
    }

    private func validateICloudConflictResolution(
        _ result: ICloudConflictResolutionResult,
        fileID: Int64
    ) throws {
        guard result.didClearConflictState else {
            throw CoreError.Internal(message: "iCloud conflict \(fileID) did not clear conflict state")
        }
        guard result.didWriteChangeLog else {
            throw CoreError.Internal(message: "iCloud conflict \(fileID) did not write change_log")
        }
    }

    private func refreshAfterICloudConflictResolution(
        fileID: Int64,
        strategy: ICloudConflictResolutionStrategy
    ) async {
        await loadCurrentCategory(currentCategory, focusingOn: fileID)
        if selection.singleFileID == fileID {
            await loadChangeLog(fileID: fileID)
        }
        iCloudConflictResolutionState = .idle
        pendingActionDestination = nil
        statusBanner = .resolvedICloudConflict(fileID: fileID, strategy: strategy)
    }

    func clearPendingActionDestination() {
        if !renameState.isRenaming,
           !deleteState.isDeleting,
           !isMovingCategory,
           !iCloudConflictResolutionState.isApplying {
            pendingActionDestination = nil
            renameState = .idle
            deleteState = .idle
            changeCategoryState = .idle
            iCloudConflictResolutionState = .idle
        }
    }

    private var isMovingCategory: Bool {
        guard let destination = pendingActionDestination else { return false }
        return changeCategoryState.isMoving(fileID: destination.fileID)
    }

    private func file(for fileID: Int64) -> FileEntrySnapshot? {
        files.first { $0.id == fileID } ??
            selectedFileDetail.flatMap { $0.id == fileID ? $0 : nil }
    }
}

extension FileEntrySnapshot {
    var hasICloudConflictCopySignal: Bool {
        let lowercasedName = currentName.lowercased()
        let lowercasedPath = path.lowercased()
        return lowercasedName.contains("conflicted copy") ||
            lowercasedPath.contains("conflicted copy")
    }
}

enum CommandPaletteLoadState: Equatable {
    case idle
    case loading(CommandIndexContext)
    case loaded(CommandPaletteSnapshot)
    case failed(CommandIndexContext, CommandPaletteSnapshot?, CoreErrorMappingSnapshot)

    var snapshot: CommandPaletteSnapshot? {
        switch self {
        case let .loaded(snapshot), let .failed(_, snapshot?, _):
            return snapshot
        case .idle, .loading, .failed:
            return nil
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

    var id: String { title }
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
}

enum CommandTargetKindSnapshot: String, Equatable {
    case command = "Command"
    case navigation = "Navigation"
    case smartList = "Smart List"
    case fileCandidate = "File Candidate"
    case recentCommand = "Recent Command"
}

enum CommandTargetActionSnapshot: String, Equatable {
    case navigate = "Navigate"
    case openSheet = "Open Sheet"
    case openConfirmation = "Open Confirmation"
    case runSmartList = "Run Smart List"
    case focusFile = "Focus File"
    case openSearch = "Open Search"
    case lowRiskAction = "Low Risk Action"
}

extension CommandTargetSnapshot {
    var isExecutable: Bool {
        !disabled && executionRoute != .unsupported
    }

    var confirmationLabel: String? {
        requiresConfirmation ? "Requires confirmation" : nil
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
        case "S2-09":
            .batchAddTags
        default:
            linkedPageRoute ?? .unsupported
        }
    }

    private var confirmationRoute: CommandPaletteTargetRoute {
        switch route {
        case "S2-12":
            .batchChangeCategory
        case "S2-13":
            .batchDelete
        case "S2-14":
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
        case "S2-19":
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
            CommandPaletteSectionSnapshot(title: CommandTargetGroupSnapshot.commands.rawValue, targets: coreIndex.commands),
            CommandPaletteSectionSnapshot(title: CommandTargetGroupSnapshot.navigation.rawValue, targets: coreIndex.navigationTargets),
            CommandPaletteSectionSnapshot(title: CommandTargetGroupSnapshot.currentSelection.rawValue, targets: coreIndex.currentSelectionTargets),
            CommandPaletteSectionSnapshot(title: CommandTargetGroupSnapshot.recent.rawValue, targets: coreIndex.recentTargets),
            CommandPaletteSectionSnapshot(title: CommandTargetGroupSnapshot.smartLists.rawValue, targets: coreIndex.smartLists),
            CommandPaletteSectionSnapshot(title: CommandTargetGroupSnapshot.fileCandidates.rawValue, targets: coreIndex.fileCandidates)
        ]
    }
}

extension CommandTargetSnapshot {
    init(coreTarget: CommandTarget) {
        id = coreTarget.id
        title = coreTarget.title
        subtitle = coreTarget.subtitle
        group = CommandTargetGroupSnapshot(coreGroup: coreTarget.group)
        kind = CommandTargetKindSnapshot(coreKind: coreTarget.kind)
        action = CommandTargetActionSnapshot(coreAction: coreTarget.action)
        route = coreTarget.route
        shortcut = coreTarget.shortcut
        disabled = coreTarget.disabled
        disabledReason = coreTarget.disabledReason
        requiresConfirmation = coreTarget.requiresConfirmation
        fileID = coreTarget.fileId
        savedSearchID = coreTarget.savedSearchId
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

private extension CommandPaletteSectionSnapshot {
    init(title: String, targets: [CommandTarget]) {
        self.title = title
        self.targets = targets.map(CommandTargetSnapshot.init(coreTarget:))
    }
}

private extension CommandTargetGroupSnapshot {
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

private extension CommandTargetKindSnapshot {
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

private extension CommandTargetActionSnapshot {
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
