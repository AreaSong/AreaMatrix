import Foundation

struct AppShellModel: Equatable {
    var statusText = "Onboarding configuration router"
}

protocol AppSettingsReading {
    func configuredRepoPath() -> String?
    func lastSuccessfulRepoOpenAt(repoPath: String) -> Int64?
}

protocol AppSettingsWriting {
    func saveConfiguredRepoPath(_ repoPath: String)
    func saveSuccessfulRepoOpen(repoPath: String, openedAt: Int64)
}

extension AppSettingsReading {
    func lastSuccessfulRepoOpenAt(repoPath _: String) -> Int64? {
        nil
    }
}

extension AppSettingsWriting {
    func saveSuccessfulRepoOpen(repoPath _: String, openedAt _: Int64) {}
}

enum AppPlatformServices {
    static var settingsReader: any AppSettingsReading {
        UserDefaultsAppSettingsReader()
    }

    static var settingsWriter: any AppSettingsWriting {
        UserDefaultsAppSettingsReader()
    }

    static var finderOpener: any RepositoryFinderOpening {
        NSWorkspaceRepositoryFinderOpener()
    }

    static var fileRevealer: any RepositoryFileRevealing {
        NSWorkspaceRepositoryFileRevealer()
    }

    static var fileOpener: any RepositoryFileOpening {
        NSWorkspaceRepositoryFileOpener()
    }

    static var localFileURLOpener: any LocalFileURLOpening {
        NSWorkspaceLocalFileURLOpener()
    }

    static var externalURLStringOpener: any ExternalURLStringOpening {
        NSWorkspaceExternalURLStringOpener()
    }

    static var pathCopier: any RepositoryPathCopying {
        NSPasteboardRepositoryPathCopier()
    }

    static var pasteboardStringWriter: any PasteboardStringWriting {
        NSPasteboardStringWriter()
    }

    static var importResultExporter: any ImportResultDetailsExporting {
        NSSavePanelImportResultDetailsExporter()
    }

    static var interactionFeedback: any AppInteractionFeedbackPerforming {
        AppKitInteractionFeedbackPerformer()
    }

    static var importBatchSessionStore: any ImportBatchSessionPersisting {
        FileImportBatchSessionStore()
    }

    static var helpOpener: any WelcomeHelpOpening {
        WelcomeHelpOpener()
    }

    static var directoryPicker: any RepositoryDirectoryPicking {
        NSOpenPanelRepositoryDirectoryPicker()
    }

    static var importPicker: any RepositoryImportPicking {
        NSOpenPanelRepositoryImportPicker()
    }

    static var windowCloser: any WindowClosing {
        NSApplicationKeyWindowCloser()
    }

    static var accessibilityAnnouncer: any AccessibilityAnnouncing {
        VoiceOverAccessibilityAnnouncer()
    }

    static var appVersionReader: any AppVersionReading {
        BundleAppVersionReader()
    }

    static var existingRepositoryMetadataReader: any ExistingRepositoryMetadataReading {
        SQLiteExistingRepositoryMetadataReader()
    }

    static var rootOverviewInspector: any RootOverviewFileInspecting {
        LocalRootOverviewFileInspector()
    }

    static var systemCapabilityChecker: any OnboardingSystemCapabilityChecking {
        LocalSystemCapabilities()
    }
}

struct UserDefaultsAppSettingsReader: AppSettingsReading {
    private let defaults: UserDefaults
    private let repoPathKey: String
    private let lastOpenKey: String

    init(defaults: UserDefaults = .standard, repoPathKey: String = "AreaMatrix.repoPath") {
        self.defaults = defaults
        self.repoPathKey = repoPathKey
        lastOpenKey = "\(repoPathKey).lastSuccessfulOpen"
    }

    func configuredRepoPath() -> String? {
        guard let value = defaults.string(forKey: repoPathKey) else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func lastSuccessfulRepoOpenAt(repoPath: String) -> Int64? {
        guard let value = defaults.dictionary(forKey: lastOpenKey)?[repoPath] else {
            return nil
        }

        if let number = value as? NSNumber { return number.int64Value }
        if let timestamp = value as? Int64 { return timestamp }
        return nil
    }
}

extension UserDefaultsAppSettingsReader: AppSettingsWriting {
    func saveConfiguredRepoPath(_ repoPath: String) {
        defaults.set(repoPath, forKey: repoPathKey)
    }

    func saveSuccessfulRepoOpen(repoPath: String, openedAt: Int64) {
        var timestamps = defaults.dictionary(forKey: lastOpenKey) ?? [:]
        timestamps[repoPath] = openedAt
        defaults.set(timestamps, forKey: lastOpenKey)
    }
}
