import Foundation

enum OnboardingPlatformServices {
    static var systemCapabilityChecker: any OnboardingSystemCapabilityChecking {
        LocalOnboardingCapabilities()
    }

    static var metadataReader: any ExistingRepositoryMetadataReading {
        SQLiteExistingRepositoryMetadataReader()
    }

    static var accessibilityAnnouncer: any AccessibilityAnnouncing {
        VoiceOverAccessibilityAnnouncer()
    }
}

struct LocalOnboardingCapabilities: OnboardingSystemCapabilityChecking {
    func isTrashAvailable() -> Bool {
        FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).isEmpty == false
    }

    func repositoryFinderAvailability(repoPath: String) -> Bool {
        FileManager.default.fileExists(atPath: repoPath)
    }
}
