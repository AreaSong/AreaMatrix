import Foundation

enum GeneralSettingsPlatformServices {
    static var rootOverviewInspector: any RootOverviewFileInspecting {
        LocalRootOverviewFileInspector()
    }

    static var rootOverviewRevealer: any RepositoryFileRevealing {
        AppPlatformServices.fileRevealer
    }

    static var ignoreRulesManager: any RepositoryIgnoreRulesManaging {
        NSWorkspaceRepositoryIgnoreRulesManager()
    }
}
