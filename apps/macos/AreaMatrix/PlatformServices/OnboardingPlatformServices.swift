import Foundation

enum OnboardingPlatformServices {
    static var systemCapabilityChecker: any OnboardingSystemCapabilityChecking {
        AppPlatformServices.systemCapabilityChecker
    }

    static var metadataReader: any ExistingRepositoryMetadataReading {
        AppPlatformServices.existingRepositoryMetadataReader
    }

    static var accessibilityAnnouncer: any AccessibilityAnnouncing {
        AppPlatformServices.accessibilityAnnouncer
    }
}

struct LocalSystemCapabilities: OnboardingSystemCapabilityChecking {
    func isTrashAvailable() -> Bool {
        FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).isEmpty == false
    }

    func repositoryFinderAvailability(repoPath: String) -> Bool {
        FileManager.default.fileExists(atPath: repoPath)
    }
}
