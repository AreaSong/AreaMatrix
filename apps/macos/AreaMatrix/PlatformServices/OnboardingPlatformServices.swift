import Foundation

struct LocalOnboardingCapabilities: OnboardingSystemCapabilityChecking {
    func isTrashAvailable() -> Bool {
        FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).isEmpty == false
    }

    func repositoryFinderAvailability(repoPath: String) -> Bool {
        FileManager.default.fileExists(atPath: repoPath)
    }
}
