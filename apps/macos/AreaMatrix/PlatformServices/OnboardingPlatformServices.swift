import AreaMatrixFeatureIngestion
import Foundation

struct LocalSystemCapabilities: OnboardingSystemCapabilityChecking {
    func isTrashAvailable() -> Bool {
        FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).isEmpty == false
    }

    func repositoryFinderAvailability(repoPath: String) -> Bool {
        FileManager.default.fileExists(atPath: repoPath)
    }
}
