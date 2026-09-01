/// Stable command-index capability surface used by Command Palette and the
/// MainList composition. It carries presentation-ready values only; execution
/// and confirmation remain feature-owned or App-owned.
public protocol CoreCommandIndexing: Sendable {
    func listCommandTargets(
        repoPath: String,
        context: CommandIndexRequestSnapshot
    ) async throws -> CoreCommandIndexSnapshot
}

public struct CommandIndexRequestSnapshot: Equatable, Sendable {
    public let query: String?
    public let selectedFileIDs: [Int64]
    public let currentPath: String?
    public let includeFileCandidates: Bool

    public init(query: String?, selectedFileIDs: [Int64], currentPath: String?, includeFileCandidates: Bool) {
        self.query = query
        self.selectedFileIDs = selectedFileIDs
        self.currentPath = currentPath
        self.includeFileCandidates = includeFileCandidates
    }
}

public struct CoreCommandIndexSnapshot: Equatable, Sendable {
    public let commands: [CoreCommandTargetSnapshot]
    public let navigationTargets: [CoreCommandTargetSnapshot]
    public let currentSelectionTargets: [CoreCommandTargetSnapshot]
    public let recentTargets: [CoreCommandTargetSnapshot]
    public let smartLists: [CoreCommandTargetSnapshot]
    public let fileCandidates: [CoreCommandTargetSnapshot]
    public let generatedAt: Int64

    public init(
        commands: [CoreCommandTargetSnapshot],
        navigationTargets: [CoreCommandTargetSnapshot],
        currentSelectionTargets: [CoreCommandTargetSnapshot],
        recentTargets: [CoreCommandTargetSnapshot],
        smartLists: [CoreCommandTargetSnapshot],
        fileCandidates: [CoreCommandTargetSnapshot],
        generatedAt: Int64
    ) {
        self.commands = commands
        self.navigationTargets = navigationTargets
        self.currentSelectionTargets = currentSelectionTargets
        self.recentTargets = recentTargets
        self.smartLists = smartLists
        self.fileCandidates = fileCandidates
        self.generatedAt = generatedAt
    }
}

public struct CoreCommandTargetSnapshot: Equatable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let group: CommandTargetGroupSnapshot
    public let kind: CommandTargetKindSnapshot
    public let action: CommandTargetActionSnapshot
    public let route: String?
    public let shortcut: String?
    public let disabled: Bool
    public let disabledReason: String?
    public let requiresConfirmation: Bool
    public let fileID: Int64?
    public let savedSearchID: Int64?

    public init(
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

public enum CommandTargetGroupSnapshot: String, Equatable, Sendable {
    case commands = "Commands"
    case navigation = "Navigation"
    case currentSelection = "Current Selection"
    case recent = "Recent"
    case smartLists = "Smart Lists"
    case fileCandidates = "File Candidates"
}

public enum CommandTargetKindSnapshot: String, Equatable, Sendable {
    case command = "Command"
    case navigation = "Navigation"
    case smartList = "Smart List"
    case fileCandidate = "File Candidate"
    case recentCommand = "Recent Command"
}

public enum CommandTargetActionSnapshot: String, Equatable, Sendable {
    case navigate = "Navigate"
    case openSheet = "Open Sheet"
    case openConfirmation = "Open Confirmation"
    case runSmartList = "Run Smart List"
    case focusFile = "Focus File"
    case openSearch = "Open Search"
    case lowRiskAction = "Low Risk Action"
}
