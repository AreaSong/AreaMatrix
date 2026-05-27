import Foundation

extension CommandPaletteSectionSnapshot {
    init(title: String, targets: [CommandTarget]) {
        self.title = title
        self.targets = targets.map(CommandTargetSnapshot.init(coreTarget:))
    }
}

extension CommandTargetGroupSnapshot {
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

extension CommandTargetKindSnapshot {
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

extension CommandTargetActionSnapshot {
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
