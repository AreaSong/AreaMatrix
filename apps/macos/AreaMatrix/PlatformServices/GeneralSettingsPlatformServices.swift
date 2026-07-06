import Foundation

enum GeneralSettingsPlatformServices {
    static var rootOverviewInspector: any RootOverviewFileInspecting {
        AppPlatformServices.rootOverviewInspector
    }

    static var rootOverviewRevealer: any RepositoryFileRevealing {
        AppPlatformServices.fileRevealer
    }

    static var ignoreRulesManager: any RepositoryIgnoreRulesManaging {
        NSWorkspaceRepositoryIgnoreRulesManager()
    }
}
