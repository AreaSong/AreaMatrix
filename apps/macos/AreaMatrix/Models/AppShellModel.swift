import AppKit
import Combine
import Foundation

struct AppShellModel: Equatable, Sendable {
    var statusText = "Onboarding configuration router"
}

protocol AppSettingsReading {
    func configuredRepoPath() -> String?
}

struct UserDefaultsAppSettingsReader: AppSettingsReading {
    private let defaults: UserDefaults
    private let repoPathKey: String

    init(defaults: UserDefaults = .standard, repoPathKey: String = "AreaMatrix.repoPath") {
        self.defaults = defaults
        self.repoPathKey = repoPathKey
    }

    func configuredRepoPath() -> String? {
        guard let value = defaults.string(forKey: repoPathKey) else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

protocol WelcomeHelpOpening {
    func openWelcomeHelp() throws
}

struct LocalWelcomeHelpOpener: WelcomeHelpOpening {
    func openWelcomeHelp() throws {
        let docsURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/product/prd.md")

        guard FileManager.default.fileExists(atPath: docsURL.path) else {
            throw WelcomeHelpError.helpDocumentUnavailable
        }

        NSWorkspace.shared.open(docsURL)
    }
}

enum WelcomeHelpError: Error, Equatable, Sendable {
    case helpDocumentUnavailable
}

struct ConfigLoadFailure: Equatable, Sendable {
    var repoPath: String
    var title: String
    var message: String
    var recoveryAction: String

    static func map(repoPath: String, error: Error) -> ConfigLoadFailure {
        if let coreError = error as? CoreError {
            return map(repoPath: repoPath, coreError: coreError)
        }

        if let bridgeError = error as? CoreBridgeError {
            return ConfigLoadFailure(
                repoPath: repoPath,
                title: "Unable to load repository settings",
                message: bridgeError.localizedDescription,
                recoveryAction: "Check the Core bridge integration, then retry opening the repository."
            )
        }

        return ConfigLoadFailure(
            repoPath: repoPath,
            title: "Unable to load repository settings",
            message: error.localizedDescription,
            recoveryAction: "Retry opening the repository or start setup again with a different folder."
        )
    }

    private static func map(repoPath: String, coreError: CoreError) -> ConfigLoadFailure {
        switch coreError {
        case .Config(let reason):
            return ConfigLoadFailure(
                repoPath: repoPath,
                title: "Repository settings are invalid",
                message: "AreaMatrix could not read the saved settings: \(reason)",
                recoveryAction: "Start setup again or choose a different repository folder."
            )
        case .PermissionDenied(let path):
            return ConfigLoadFailure(
                repoPath: repoPath,
                title: "Repository settings need permission",
                message: "AreaMatrix cannot read repository settings at \(path).",
                recoveryAction: "Grant folder access, then retry opening the repository."
            )
        case .Io(let message):
            return ConfigLoadFailure(
                repoPath: repoPath,
                title: "Repository settings are unavailable",
                message: "File system error while reading settings: \(message)",
                recoveryAction: "Make sure the folder is available, then retry."
            )
        case .Db(let message):
            return ConfigLoadFailure(
                repoPath: repoPath,
                title: "Repository metadata cannot be opened",
                message: "Database error while reading settings: \(message)",
                recoveryAction: "Retry opening the repository or start setup again."
            )
        default:
            return ConfigLoadFailure(
                repoPath: repoPath,
                title: "Unable to load repository settings",
                message: coreError.localizedDescription,
                recoveryAction: "Retry opening the repository or start setup again with a different folder."
            )
        }
    }
}

final class OnboardingModel: ObservableObject {
    enum Route: Equatable, Sendable {
        case loadingConfiguration
        case welcome
        case repositoryReady(RepoConfigSnapshot)
        case configurationError(ConfigLoadFailure)
    }

    enum WelcomeAction: Equatable, Sendable {
        case continueRequested
    }

    @Published private(set) var route: Route = .loadingConfiguration
    @Published private(set) var toastMessage: String?
    @Published private(set) var welcomeAction: WelcomeAction?

    private let settingsReader: any AppSettingsReading
    private let configLoader: any CoreConfigurationLoading
    private let helpOpener: any WelcomeHelpOpening
    private var didBootstrap = false

    init(
        settingsReader: any AppSettingsReading = UserDefaultsAppSettingsReader(),
        configLoader: any CoreConfigurationLoading = CoreBridge(),
        helpOpener: any WelcomeHelpOpening = LocalWelcomeHelpOpener()
    ) {
        self.settingsReader = settingsReader
        self.configLoader = configLoader
        self.helpOpener = helpOpener
    }

    @MainActor
    func bootstrapIfNeeded() async {
        guard !didBootstrap else {
            return
        }

        didBootstrap = true
        await loadConfiguredRepository()
    }

    @MainActor
    func retryConfigurationLoad() async {
        await loadConfiguredRepository()
    }

    @MainActor
    func showWelcome() {
        route = .welcome
        toastMessage = nil
    }

    @MainActor
    func continueFromWelcome() {
        welcomeAction = .continueRequested
    }

    @MainActor
    func openLearnMore() {
        do {
            try helpOpener.openWelcomeHelp()
        } catch {
            toastMessage = "Learn more is unavailable right now."
        }
    }

    @MainActor
    func clearToast() {
        toastMessage = nil
    }

    @MainActor
    private func loadConfiguredRepository() async {
        guard let repoPath = settingsReader.configuredRepoPath() else {
            route = .welcome
            return
        }

        route = .loadingConfiguration

        do {
            let config = try await configLoader.loadConfig(repoPath: repoPath)
            route = .repositoryReady(config)
        } catch {
            route = .configurationError(ConfigLoadFailure.map(repoPath: repoPath, error: error))
        }
    }
}
