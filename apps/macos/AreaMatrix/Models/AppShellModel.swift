import Combine
import Foundation

final class OnboardingModel: ObservableObject {
    enum Route: Equatable, Sendable {
        case loadingConfiguration
        case welcome
        case choosePath
        case validatePath
        case confirmRepositoryInitialization(RepositoryInitializationDraft)
        case initializing(RepositoryInitializationDraft)
        case initializationFailed(String, CoreErrorMappingSnapshot?)
        case mainLoading(String)
        case mainRepoError(String, CoreErrorMappingSnapshot?)
        case dbRepairConfirm(String, ScanSessionSnapshot?, CoreErrorMappingSnapshot?)
        case settingsRepository
        case repositoryReady(RepoConfigSnapshot)
        case configurationError(ConfigLoadFailure)
    }

    enum ChoosePathAction: Equatable, Sendable {
        case continueRequested(RepoPathValidationSnapshot)
    }

    enum ValidatePathAction: Equatable, Sendable {
        case continueRequested(RepoPathValidationSnapshot)
        case adoptExistingRequested(RepoPathValidationSnapshot, scanSession: ScanSessionSnapshot?)
        case openExistingRepositoryRequested(RepoPathValidationSnapshot)
    }

    private static let defaultRepositoryPathDisplay = "~/AreaMatrix/"
    @Published private(set) var route: Route = .loadingConfiguration
    @Published private(set) var toastMessage: String?
    @Published private(set) var choosePathAction: ChoosePathAction?
    @Published private(set) var validatePathAction: ValidatePathAction?
    @Published private(set) var repositoryPathText = OnboardingModel.defaultRepositoryPathDisplay
    @Published private(set) var repositoryPathError: String?
    @Published private(set) var repositoryPathErrorMapping: CoreErrorMappingSnapshot?
    @Published private(set) var repositoryPathValidation: RepoPathValidationSnapshot?
    @Published private(set) var existingRepositoryMetadata: ExistingRepositoryMetadataSnapshot?
    @Published private(set) var latestScanSession: ScanSessionSnapshot?
    @Published var initializationScanSession: ScanSessionSnapshot?
    @Published var initializationProgressWarning: String?
    @Published private(set) var isValidatingRepositoryPath = false
    @Published private(set) var isICloudRiskAccepted = false
    @Published private(set) var isSetupQuitConfirmationPresented = false

    var canContinueFromChoosePath: Bool { !isValidatingRepositoryPath && repositoryPathError == nil }

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

    var validatePathReturnRouteIsSettings: Bool { validatePathReturnRoute == .settingsRepository }
    private let settingsReader: any AppSettingsReading
    private let settingsWriter: any AppSettingsWriting
    private let configLoader: any CoreConfigurationLoading
    private let pathValidator: any CoreRepositoryPathValidating
    let repositoryInitializer: any CoreRepositoryInitializing
    private let existingRepositoryMetadataReader: any ExistingRepositoryMetadataReading
    let scanSessionReader: any CoreScanSessionReading
    let errorMapper: any CoreErrorMapping
    private let helpOpener: any WelcomeHelpOpening
    private let directoryPicker: any RepositoryDirectoryPicking
    private var didBootstrap = false
    private var validatePathReturnRoute: Route = .choosePath
    var initializationProgressTask: Task<Void, Never>?

    init(
        settingsReader: any AppSettingsReading = UserDefaultsAppSettingsReader(),
        settingsWriter: any AppSettingsWriting = UserDefaultsAppSettingsReader(),
        configLoader: any CoreConfigurationLoading = CoreBridge(),
        pathValidator: any CoreRepositoryPathValidating = CoreBridge(),
        repositoryInitializer: any CoreRepositoryInitializing = CoreBridge(),
        existingRepositoryMetadataReader: any ExistingRepositoryMetadataReading =
            SQLiteExistingRepositoryMetadataReader(),
        scanSessionReader: any CoreScanSessionReading = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge(),
        helpOpener: any WelcomeHelpOpening = LocalWelcomeHelpOpener(),
        directoryPicker: any RepositoryDirectoryPicking = NSOpenPanelRepositoryDirectoryPicker()
    ) {
        self.settingsReader = settingsReader
        self.settingsWriter = settingsWriter
        self.configLoader = configLoader
        self.pathValidator = pathValidator
        self.repositoryInitializer = repositoryInitializer
        self.existingRepositoryMetadataReader = existingRepositoryMetadataReader
        self.scanSessionReader = scanSessionReader
        self.errorMapper = errorMapper
        self.helpOpener = helpOpener
        self.directoryPicker = directoryPicker
    }

    @MainActor
    func bootstrapIfNeeded() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        await loadConfiguredRepository()
    }
    @MainActor
    func retryConfigurationLoad() async { await loadConfiguredRepository() }
    @MainActor
    func showWelcome() { route = .welcome; toastMessage = nil }
    @MainActor
    func showChoosePath() {
        if validatePathReturnRoute != .settingsRepository { validatePathReturnRoute = .choosePath }
        route = .choosePath
        toastMessage = nil
        repositoryPathErrorMapping = nil
        repositoryPathError = localRepositoryPathError(for: repositoryPathText)
    }
    @MainActor
    func showValidatePath() { route = .validatePath; toastMessage = nil }
    @MainActor
    func returnFromChoosePath() { validatePathReturnRouteIsSettings ? returnFromValidatePath() : showWelcome() }
    @MainActor
    func beginSettingsRepositoryPathValidation(_ repoPath: String) async {
        validatePathReturnRoute = .settingsRepository
        updateRepositoryPath(repoPath)
        route = .validatePath
        repositoryPathValidation = nil
        existingRepositoryMetadata = nil
        validatePathAction = nil
        isICloudRiskAccepted = false
        await validateSelectedRepositoryPath()
    }

    @MainActor
    func returnFromValidatePath() {
        route = validatePathReturnRoute
        toastMessage = nil
        repositoryPathErrorMapping = nil
    }

    @MainActor
    func continueFromWelcome() {
        route = .choosePath
        toastMessage = nil
        repositoryPathError = localRepositoryPathError(for: repositoryPathText)
    }

    @MainActor
    func updateRepositoryPath(_ value: String) {
        repositoryPathText = value
        repositoryPathValidation = nil
        existingRepositoryMetadata = nil
        latestScanSession = nil
        initializationScanSession = nil
        initializationProgressWarning = nil
        choosePathAction = nil
        validatePathAction = nil
        repositoryPathErrorMapping = nil
        toastMessage = nil
        isICloudRiskAccepted = false
        repositoryPathError = localRepositoryPathError(for: value)
    }

    @MainActor
    func chooseRepositoryPath() {
        guard let selectedURL = directoryPicker.chooseDirectory() else { return }
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
        if validatePathReturnRoute != .settingsRepository { validatePathReturnRoute = .choosePath }
        repositoryPathValidation = nil
        existingRepositoryMetadata = nil
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
    func updateICloudRiskAccepted(_ isAccepted: Bool) { isICloudRiskAccepted = isAccepted }
    @MainActor
    func continueFromValidatePath() {
        guard canContinueFromValidatePath, let validation = repositoryPathValidation else {
            return
        }

        if validation.isInitialized {
            validatePathAction = .openExistingRepositoryRequested(validation)
            openExistingRepository(validation)
        } else {
            switch validation.recommendedMode {
            case .adoptExisting:
                validatePathAction = .adoptExistingRequested(validation, scanSession: latestScanSession)
                route = .confirmRepositoryInitialization(RepositoryInitializationDraft(
                    validation: validation,
                    mode: .adoptExisting,
                    scanSession: latestScanSession
                ))
            default:
                validatePathAction = .continueRequested(validation)
                route = .confirmRepositoryInitialization(RepositoryInitializationDraft(
                    validation: validation,
                    mode: .createEmpty,
                    scanSession: nil
                ))
            }
        }
    }

    @MainActor
    func openExistingRepository(_ validation: RepoPathValidationSnapshot) {
        if validatePathReturnRoute != .settingsRepository {
            settingsWriter.saveConfiguredRepoPath(validation.repoPath)
        }
        route = .mainLoading(validation.repoPath)
    }

    @MainActor
    func createEmptyRepositoryFromConfirmInit() async { await initializeRepositoryFromConfirmInit(mode: .createEmpty) }

    @MainActor
    func adoptExistingRepositoryFromConfirmInit() async {
        await initializeRepositoryFromConfirmInit(mode: .adoptExisting)
    }

    var shouldConfirmSetupExit: Bool {
        if route == .validatePath { return true }
        if case .confirmRepositoryInitialization = route { return true }
        return false
    }

    @MainActor
    func requestSetupQuit() {
        guard shouldConfirmSetupExit else { return }
        isSetupQuitConfirmationPresented = true
    }

    @MainActor
    func cancelSetupQuit() { isSetupQuitConfirmationPresented = false }
    @MainActor
    @discardableResult
    func confirmSetupQuit() -> Bool {
        let shouldCloseWindow = validatePathReturnRoute != .settingsRepository
        isSetupQuitConfirmationPresented = false
        validatePathAction = nil
        repositoryPathValidation = nil
        existingRepositoryMetadata = nil
        latestScanSession = nil
        initializationScanSession = nil
        initializationProgressWarning = nil
        stopInitializationProgressPolling()
        route = shouldCloseWindow ? .welcome : .settingsRepository
        return shouldCloseWindow
    }

    @MainActor
    private func validateSelectedRepositoryPath() async {
        isValidatingRepositoryPath = true
        choosePathAction = nil
        latestScanSession = nil
        existingRepositoryMetadata = nil
        repositoryPathErrorMapping = nil
        repositoryPathError = nil
        defer {
            isValidatingRepositoryPath = false
        }

        do {
            let normalizedPath = Self.normalizedRepositoryPath(repositoryPathText)
            let validation = try await pathValidator.validateRepoPath(repoPath: normalizedPath)
            repositoryPathValidation = validation
            repositoryPathErrorMapping = nil

            if shouldLoadLatestScanSession(for: validation) {
                do {
                    latestScanSession = try await scanSessionReader.latestScanSession(repoPath: validation.repoPath)
                } catch {
                    await routeValidationFailure(error, repoPath: validation.repoPath)
                    return
                }
            }

            if validation.hasUnfinishedScanSession || validation.issues.contains(.unfinishedScanSession) {
                route = .dbRepairConfirm(validation.repoPath, latestScanSession, nil)
                return
            }

            if validation.isInitialized {
                do {
                    existingRepositoryMetadata = try await existingRepositoryMetadataReader.metadata(
                        repoPath: validation.repoPath
                    )
                } catch {
                    await routeValidationFailure(error, repoPath: validation.repoPath)
                    return
                }
            }

            repositoryPathError = validatePathBlockingMessage(for: validation)
            repositoryPathErrorMapping = nil

            if repositoryPathError != nil {
                return
            }

            choosePathAction = .continueRequested(validation)
        } catch {
            repositoryPathValidation = nil
            await routeValidationFailure(error, repoPath: Self.normalizedRepositoryPath(repositoryPathText))
        }
    }

    @MainActor
    private func initializeRepositoryFromConfirmInit(mode: RepoInitModeSnapshot) async {
        guard case .confirmRepositoryInitialization(let draft) = route, draft.mode == mode else { return }

        let repoPath = draft.validation.repoPath
        initializationScanSession = draft.scanSession
        initializationProgressWarning = nil
        route = .initializing(draft)
        startInitializationProgressPolling(repoPath: repoPath, mode: mode)
        defer { stopInitializationProgressPolling() }

        do {
            let latestValidation = try await pathValidator.validateRepoPath(repoPath: repoPath)
            guard Self.validationStillMatchesConfirmMode(latestValidation, mode: mode) else {
                repositoryPathValidation = latestValidation
                repositoryPathError = "路径状态已变化，请返回重新校验"
                route = .validatePath
                return
            }

            try await initializeRepository(repoPath: repoPath, mode: mode)
            settingsWriter.saveConfiguredRepoPath(repoPath)
            route = .mainLoading(repoPath)
        } catch {
            await routeInitializationFailure(error, repoPath: repoPath)
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
    private func loadConfiguredRepository() async {
        guard let repoPath = settingsReader.configuredRepoPath() else { route = .welcome; return }
        route = .loadingConfiguration

        do {
            let config = try await configLoader.loadConfig(repoPath: repoPath)
            route = .repositoryReady(config)
        } catch {
            route = .configurationError(ConfigLoadFailure.map(repoPath: repoPath, error: error))
        }
    }

    private func validatePathBlockingMessage(for validation: RepoPathValidationSnapshot) -> String? {
        let checks: [(Bool, String)] = [
            (
                validation.isInsideAreaMatrix || validation.issues.contains(.insideAreaMatrix),
                "请选择资料库根目录，而不是 .areamatrix 内部目录"
            ),
            (
                !validation.exists || validation.issues.contains(.missingPath),
                "路径不存在，请选择已存在的文件夹"
            ),
            (!validation.isDirectory || validation.issues.contains(.notDirectory), "请选择文件夹路径"),
            (
                !validation.isReadable || validation.issues.contains(.notReadable),
                "AreaMatrix 没有读取该位置的权限"
            ),
            (
                !validation.isWritable || validation.issues.contains(.notWritable),
                "AreaMatrix 没有写入该位置的权限"
            ),
            (validation.hasInsufficientAvailableCapacity, "可用空间不足，请释放空间或选择其他路径"),
            (validation.hasMissingEnvironmentChecks, "路径环境检查缺失，请重试或选择其他路径"),
            (
                validation.hasUnfinishedScanSession || validation.issues.contains(.unfinishedScanSession),
                "该资料库存在未完成的扫描记录，请先进入修复流程"
            ),
            (
                validation.recommendedMode == nil && !validation.isInitialized,
                "该路径暂时不能作为资料库使用"
            ),
        ]

        return checks.first { $0.0 }?.1
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
        return normalized.split(separator: "/", omittingEmptySubsequences: true).contains(".areamatrix")
    }

    @MainActor
    private func routeValidationFailure(
        _ error: Error,
        repoPath: String
    ) async {
        guard let coreError = error as? CoreError else {
            repositoryPathErrorMapping = nil
            repositoryPathError = "路径字符串无法解析"
            return
        }

        let mapping = await errorMapper.mapCoreError(coreError)
        repositoryPathErrorMapping = mapping
        repositoryPathError = mapping.userMessage

        switch coreError {
        case .Db:
            route = .dbRepairConfirm(repoPath, latestScanSession, mapping)
        case .Config, .Internal, .RepoNotInitialized:
            route = .mainRepoError(repoPath, mapping)
        default:
            route = .validatePath
        }
    }

    @MainActor
    private func routeInitializationFailure(
        _ error: Error,
        repoPath: String
    ) async {
        guard let coreError = error as? CoreError else {
            route = .initializationFailed(repoPath, nil)
            return
        }

        let mapping = await errorMapper.mapCoreError(coreError)
        route = .initializationFailed(repoPath, mapping)
    }
}
