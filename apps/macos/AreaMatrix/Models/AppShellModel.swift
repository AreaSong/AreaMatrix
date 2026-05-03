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

protocol RepositoryDirectoryPicking {
    @MainActor
    func chooseDirectory() -> URL?
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

struct NSOpenPanelRepositoryDirectoryPicker: RepositoryDirectoryPicking {
    @MainActor
    func chooseDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Choose"
        panel.message = "Choose a repository folder."

        return panel.runModal() == .OK ? panel.url : nil
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
        case choosePath
        case validatePath
        case repositoryReady(RepoConfigSnapshot)
        case configurationError(ConfigLoadFailure)
    }

    enum WelcomeAction: Equatable, Sendable {
        case continueRequested
    }

    enum ChoosePathAction: Equatable, Sendable {
        case continueRequested(RepoPathValidationSnapshot)
    }

    enum ValidatePathAction: Equatable, Sendable {
        case continueRequested(RepoPathValidationSnapshot)
        case openExistingRepositoryRequested(RepoPathValidationSnapshot)
    }

    private static let defaultRepositoryPathDisplay = "~/AreaMatrix/"

    @Published private(set) var route: Route = .loadingConfiguration
    @Published private(set) var toastMessage: String?
    @Published private(set) var welcomeAction: WelcomeAction?
    @Published private(set) var choosePathAction: ChoosePathAction?
    @Published private(set) var validatePathAction: ValidatePathAction?
    @Published private(set) var repositoryPathText = OnboardingModel.defaultRepositoryPathDisplay
    @Published private(set) var repositoryPathError: String?
    @Published private(set) var repositoryPathValidation: RepoPathValidationSnapshot?
    @Published private(set) var isValidatingRepositoryPath = false
    @Published private(set) var isICloudRiskAccepted = false

    var canContinueFromChoosePath: Bool {
        !isValidatingRepositoryPath && repositoryPathError == nil
    }

    var canContinueFromValidatePath: Bool {
        guard !isValidatingRepositoryPath, let validation = repositoryPathValidation else {
            return false
        }

        if validatePathBlockingMessage(for: validation) != nil {
            return false
        }

        if validation.isICloudPath && !isICloudRiskAccepted {
            return false
        }

        return validation.recommendedMode != nil || validation.isInitialized
    }

    var validatePathPrimaryActionTitle: String {
        repositoryPathValidation?.isInitialized == true ? "Open Repository" : "Continue"
    }

    private let settingsReader: any AppSettingsReading
    private let configLoader: any CoreConfigurationLoading
    private let pathValidator: any CoreRepositoryPathValidating
    private let helpOpener: any WelcomeHelpOpening
    private let directoryPicker: any RepositoryDirectoryPicking
    private var didBootstrap = false

    init(
        settingsReader: any AppSettingsReading = UserDefaultsAppSettingsReader(),
        configLoader: any CoreConfigurationLoading = CoreBridge(),
        pathValidator: any CoreRepositoryPathValidating = CoreBridge(),
        helpOpener: any WelcomeHelpOpening = LocalWelcomeHelpOpener(),
        directoryPicker: any RepositoryDirectoryPicking = NSOpenPanelRepositoryDirectoryPicker()
    ) {
        self.settingsReader = settingsReader
        self.configLoader = configLoader
        self.pathValidator = pathValidator
        self.helpOpener = helpOpener
        self.directoryPicker = directoryPicker
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
    func showChoosePath() {
        route = .choosePath
        toastMessage = nil
        repositoryPathError = localRepositoryPathError(for: repositoryPathText)
    }

    @MainActor
    func continueFromWelcome() {
        welcomeAction = .continueRequested
        route = .choosePath
        toastMessage = nil
        repositoryPathError = localRepositoryPathError(for: repositoryPathText)
    }

    @MainActor
    func updateRepositoryPath(_ value: String) {
        repositoryPathText = value
        repositoryPathValidation = nil
        choosePathAction = nil
        validatePathAction = nil
        toastMessage = nil
        isICloudRiskAccepted = false
        repositoryPathError = localRepositoryPathError(for: value)
    }

    @MainActor
    func chooseRepositoryPath() {
        guard let selectedURL = directoryPicker.chooseDirectory() else {
            return
        }

        updateRepositoryPath(selectedURL.path)
    }

    @MainActor
    func useDefaultRepositoryPath() async {
        updateRepositoryPath(Self.defaultRepositoryPathDisplay)
        await continueFromChoosePath()
    }

    @MainActor
    func continueFromChoosePath() async {
        guard repositoryPathError == nil else {
            return
        }

        route = .validatePath
        repositoryPathValidation = nil
        validatePathAction = nil
        isICloudRiskAccepted = false
        await validateSelectedRepositoryPath()
    }

    @MainActor
    func retryRepositoryPathValidation() async {
        validatePathAction = nil
        await validateSelectedRepositoryPath()
    }

    @MainActor
    func updateICloudRiskAccepted(_ isAccepted: Bool) {
        isICloudRiskAccepted = isAccepted
    }

    @MainActor
    func continueFromValidatePath() {
        guard canContinueFromValidatePath, let validation = repositoryPathValidation else {
            return
        }

        if validation.isInitialized {
            validatePathAction = .openExistingRepositoryRequested(validation)
        } else {
            validatePathAction = .continueRequested(validation)
        }
    }

    @MainActor
    private func validateSelectedRepositoryPath() async {
        isValidatingRepositoryPath = true
        choosePathAction = nil
        repositoryPathError = nil
        defer {
            isValidatingRepositoryPath = false
        }

        do {
            let normalizedPath = Self.normalizedRepositoryPath(repositoryPathText)
            let validation = try await pathValidator.validateRepoPath(repoPath: normalizedPath)
            repositoryPathValidation = validation
            repositoryPathError = validatePathBlockingMessage(for: validation)

            if repositoryPathError != nil {
                return
            }

            choosePathAction = .continueRequested(validation)
        } catch {
            repositoryPathValidation = nil
            repositoryPathError = Self.repositoryPathValidationErrorMessage(for: error)
        }
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

    private func validatePathBlockingMessage(for validation: RepoPathValidationSnapshot) -> String? {
        if validation.isInsideAreaMatrix || validation.issues.contains(.insideAreaMatrix) {
            return "请选择资料库根目录，而不是 .areamatrix 内部目录"
        }

        if !validation.exists || validation.issues.contains(.missingPath) {
            return "路径不存在，请选择已存在的文件夹"
        }

        if !validation.isDirectory || validation.issues.contains(.notDirectory) {
            return "请选择文件夹路径"
        }

        if !validation.isReadable || validation.issues.contains(.notReadable) {
            return "AreaMatrix 没有读取该位置的权限"
        }

        if !validation.isWritable || validation.issues.contains(.notWritable) {
            return "AreaMatrix 没有写入该位置的权限"
        }

        if validation.hasUnfinishedScanSession || validation.issues.contains(.unfinishedScanSession) {
            return "该资料库存在未完成的扫描记录，请先进入修复流程"
        }

        if validation.recommendedMode == nil && !validation.isInitialized {
            return "该路径暂时不能作为资料库使用"
        }

        return nil
    }

    private func localRepositoryPathError(for value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return "请输入资料库路径"
        }

        if trimmed.contains("\0") {
            return "路径字符串无法解析"
        }

        if Self.pathContainsAreaMatrixComponent(trimmed) {
            return "请选择资料库根目录，而不是 .areamatrix 内部目录"
        }

        return nil
    }

    private static func normalizedRepositoryPath(_ value: String) -> String {
        (value.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
    }

    private static func pathContainsAreaMatrixComponent(_ value: String) -> Bool {
        let normalized = normalizedRepositoryPath(value)
        return normalized
            .split(separator: "/", omittingEmptySubsequences: true)
            .contains(".areamatrix")
    }

    private static func repositoryPathValidationErrorMessage(for error: Error) -> String {
        guard let coreError = error as? CoreError else {
            return "路径字符串无法解析"
        }

        switch coreError {
        case .InvalidPath:
            return "路径字符串无法解析"
        case .PermissionDenied:
            return "AreaMatrix 没有读取该位置的权限"
        case .ICloudPlaceholder:
            return "该位置仍是 iCloud 占位内容，无法校验"
        default:
            return "路径字符串无法解析"
        }
    }
}
