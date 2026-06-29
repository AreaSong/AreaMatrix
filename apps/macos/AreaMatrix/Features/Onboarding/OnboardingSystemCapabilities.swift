import Foundation

protocol OnboardingSystemCapabilityChecking {
    func isTrashAvailable() -> Bool
    func repositoryFinderAvailability(repoPath: String) -> Bool
}
