@testable import AreaMatrix

struct NoopWelcomeHelpOpener: WelcomeHelpOpening {
    func openWelcomeHelp() throws {}
}

struct StaticOnboardingSystemCapabilityChecker: OnboardingSystemCapabilityChecking {
    var isTrashAvailableValue = true
    var repositoryFinderAvailabilityByPath: [String: Bool] = [:]

    func isTrashAvailable() -> Bool {
        isTrashAvailableValue
    }

    func repositoryFinderAvailability(repoPath: String) -> Bool {
        repositoryFinderAvailabilityByPath[repoPath] ?? true
    }
}
