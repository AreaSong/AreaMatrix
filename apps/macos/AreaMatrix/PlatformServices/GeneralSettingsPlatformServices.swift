import Foundation

enum GeneralSettingsPlatformServices {
    static func makeIgnoreRulesManager(
        localURLOpener: any LocalFileURLOpening
    ) -> any RepositoryIgnoreRulesManaging {
        NSWorkspaceRepositoryIgnoreRulesManager(localURLOpener: localURLOpener)
    }
}
