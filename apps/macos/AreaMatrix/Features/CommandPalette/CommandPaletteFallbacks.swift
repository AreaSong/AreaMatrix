import Foundation

extension CommandPaletteSnapshot {
    static func noRepositoryCommands() -> CommandPaletteSnapshot {
        CommandPaletteSnapshot(
            sections: [
                CommandPaletteSectionSnapshot(
                    title: CommandTargetGroupSnapshot.commands.displayName,
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
                CommandPaletteSectionSnapshot(title: CommandTargetGroupSnapshot.commands.displayName, targets: targets)
            ],
            generatedAt: 0
        )
    }
}

extension CommandTargetSnapshot {
    static var importFiles: CommandTargetSnapshot {
        CommandTargetSnapshot(
            id: "fallback.import",
            title: L10n.string("Import files..."),
            subtitle: L10n.string("Open the import sheet"),
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
    }

    static var openRepository: CommandTargetSnapshot {
        CommandTargetSnapshot(
            id: "fallback.openRepository",
            title: L10n.string("Open repository..."),
            subtitle: L10n.string("Choose a repository folder"),
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
    }

    static var settings: CommandTargetSnapshot {
        CommandTargetSnapshot(
            id: "fallback.settings",
            title: L10n.string("Settings"),
            subtitle: L10n.string("Open app settings"),
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
    }

    static var help: CommandTargetSnapshot {
        CommandTargetSnapshot(
            id: "fallback.help",
            title: L10n.string("Help"),
            subtitle: L10n.string("Open help"),
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
}
