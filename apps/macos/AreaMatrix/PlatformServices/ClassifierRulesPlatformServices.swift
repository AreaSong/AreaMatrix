enum ClassifierSettingsPlatformServices {
    static var fileOpener: any RepositoryFileOpening {
        AppPlatformServices.fileOpener
    }

    static var fileRevealer: any RepositoryFileRevealing {
        AppPlatformServices.fileRevealer
    }

    static var finderOpener: any RepositoryFinderOpening {
        AppPlatformServices.finderOpener
    }

    static var accessibilityAnnouncer: any AccessibilityAnnouncing {
        AppPlatformServices.accessibilityAnnouncer
    }
}
