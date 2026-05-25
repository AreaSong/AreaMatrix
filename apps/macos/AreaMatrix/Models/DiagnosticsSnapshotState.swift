import Foundation

protocol CoreDiagnosticsCollecting: Sendable {
    func createDiagnosticsSnapshot(repoPath: String) async throws -> DiagnosticsSnapshotSnapshot
}

struct DiagnosticsSnapshotSnapshot: Equatable {
    var snapshotPath: String
    var createdAt: Int64
    var warnings: [String]
}

enum MainRepoDiagnosticsState: Equatable {
    case idle
    case confirmingPrivacy
    case collecting
    case collected(DiagnosticsSnapshotSnapshot)
    case failed(CoreErrorMappingSnapshot)
}

extension DiagnosticsSnapshotSnapshot {
    init(coreSnapshot: DiagnosticsSnapshot) {
        snapshotPath = coreSnapshot.snapshotPath
        createdAt = coreSnapshot.createdAt
        warnings = coreSnapshot.warnings
    }
}

extension CommandPaletteSnapshot {
    static func noRepositoryCommands() -> CommandPaletteSnapshot {
        CommandPaletteSnapshot(
            sections: [
                CommandPaletteSectionSnapshot(
                    title: CommandTargetGroupSnapshot.commands.rawValue,
                    targets: [.openRepository, .settings, .help]
                )
            ],
            generatedAt: 0
        )
    }

    static func commandRegistryRecovery(query: String?) -> CommandPaletteSnapshot {
        let targets = [CommandTargetSnapshot.importFiles, .settings, .help].filter { target in
            guard let query, !query.isEmpty else { return true }
            return target.title.localizedCaseInsensitiveContains(query)
        }
        return CommandPaletteSnapshot(
            sections: [
                CommandPaletteSectionSnapshot(title: CommandTargetGroupSnapshot.commands.rawValue, targets: targets)
            ],
            generatedAt: 0
        )
    }
}

extension CommandTargetSnapshot {
    static let importFiles = CommandTargetSnapshot(
        id: "fallback.import",
        title: "Import files...",
        subtitle: "Open the import sheet",
        group: .commands,
        kind: .command,
        action: .openSheet,
        route: "import",
        shortcut: "Cmd+I",
        disabled: false,
        disabledReason: nil,
        requiresConfirmation: false,
        fileID: nil,
        savedSearchID: nil
    )

    static let openRepository = CommandTargetSnapshot(
        id: "fallback.openRepository",
        title: "Open repository...",
        subtitle: "Choose a repository folder",
        group: .commands,
        kind: .command,
        action: .navigate,
        route: "openRepository",
        shortcut: nil,
        disabled: false,
        disabledReason: nil,
        requiresConfirmation: false,
        fileID: nil,
        savedSearchID: nil
    )

    static let settings = CommandTargetSnapshot(
        id: "fallback.settings",
        title: "Settings",
        subtitle: "Open app settings",
        group: .commands,
        kind: .command,
        action: .navigate,
        route: "settings",
        shortcut: nil,
        disabled: false,
        disabledReason: nil,
        requiresConfirmation: false,
        fileID: nil,
        savedSearchID: nil
    )

    static let help = CommandTargetSnapshot(
        id: "fallback.help",
        title: "Help",
        subtitle: "Open help",
        group: .commands,
        kind: .command,
        action: .navigate,
        route: "help",
        shortcut: nil,
        disabled: false,
        disabledReason: nil,
        requiresConfirmation: false,
        fileID: nil,
        savedSearchID: nil
    )
}
