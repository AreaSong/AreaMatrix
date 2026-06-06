import Foundation

@MainActor
final class ConnectRepositoryModel: ObservableObject {
    enum CheckState: Equatable {
        case idle
        case checking(String)
    }

    @Published private(set) var checkState: CheckState = .idle
    @Published private(set) var recentRepositories: [RecentRepository] = []
    @Published private(set) var error: MobileRepositoryConnectionError?
    @Published private(set) var route: MobileRepositoryConnectionRoute?
    @Published private(set) var latestValidation: MobileRepositoryValidation?
    @Published private(set) var latestCloudState: MobileCloudStorageState?
    @Published private(set) var shareImportTakeoverConnection: MobileRepositoryConnection?

    private let bridge: any MobileRepositoryCoreBridge
    private let accessService: any RepositoryAccessServicing
    private let now: @Sendable () -> Date

    init(
        bridge: any MobileRepositoryCoreBridge,
        accessService: any RepositoryAccessServicing = SecurityScopedRepositoryAccessService(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.bridge = bridge
        self.accessService = accessService
        self.now = now
    }

    var isChecking: Bool {
        if case .checking = checkState { return true }
        return false
    }

    func loadRecentRepositories() async {
        recentRepositories = await accessService.recentRepositories()
    }

    @discardableResult
    func connectICloudRepository() async -> Bool {
        prepareForPicker()
        guard await accessService.isICloudDriveAvailable() else {
            applyCloudFailure(.unavailable(
                "iCloud Drive 不可用，"
                    + "请在系统设置中启用 iCloud Drive 后重试。"
            ))
            return false
        }
        return true
    }

    func connectSelectedURL(_ url: URL) async {
        await connect(url: url)
    }

    @discardableResult
    func reconnect(_ recent: RecentRepository) async -> Bool {
        guard recent.accessStatus == .available else {
            prepareForPicker()
            return true
        }
        do {
            let url = try await accessService.resolveBookmark(for: recent)
            await connect(url: url)
            return false
        } catch {
            applyFailure(.accessExpired(recent.pathDisplay))
            return true
        }
    }

    func cancelSystemPicker() {
        checkState = .idle
    }

    func dismissRoute() {
        route = nil
    }

    func handleOpenURL(_ url: URL) async {
        guard url.scheme == "areamatrix", url.host == "share-import" else { return }
        await openRecentRepositoryForShareImport()
    }

    private func openRecentRepositoryForShareImport() async {
        let repositories = await accessService.recentRepositories()
        guard let recent = repositories.first else {
            applyFailure(.unavailable("Open AreaMatrix to connect a repository."))
            return
        }
        guard recent.accessStatus == .available else {
            applyFailure(.accessExpired(recent.pathDisplay))
            return
        }
        do {
            let url = try await accessService.resolveBookmark(for: recent)
            try await routeShareImportRepository(url: url, recent: recent)
        } catch {
            applyFailure(Self.connectionError(from: error))
        }
    }

    private func prepareForPicker() {
        checkState = .idle
        error = nil
        route = nil
        latestValidation = nil
        latestCloudState = nil
        shareImportTakeoverConnection = nil
    }

    private func connect(url: URL) async {
        guard url.isFileURL else {
            applyFailure(.invalidPath(url.absoluteString))
            return
        }
        shareImportTakeoverConnection = nil
        beginChecking(url)
        do {
            let scopedAccess = try await accessService.beginAccessing(url)
            defer { scopedAccess.stop() }
            let validation = try await bridge.validateRepoPath(repoPath: url.path)
            try await routeValidatedRepository(validation, sourceURL: url)
        } catch {
            applyFailure(Self.connectionError(from: error))
        }
    }

    private func routeShareImportRepository(url: URL, recent: RecentRepository) async throws {
        guard url.isFileURL else {
            applyFailure(.invalidPath(url.absoluteString))
            return
        }
        beginChecking(url)
        let scopedAccess = try await accessService.beginAccessing(url)
        defer { scopedAccess.stop() }
        let validation = try await bridge.validateRepoPath(repoPath: url.path)
        if let blockingError = Self.blockingError(for: validation) {
            applyFailure(blockingError)
            return
        }
        let config = try await bridge.loadConfig(repoPath: validation.repoPath)
        checkState = .idle
        shareImportTakeoverConnection = MobileRepositoryConnection(
            validation: validation,
            config: config,
            bookmark: RepositoryBookmark(
                url: url,
                displayName: recent.displayName,
                pathDisplay: recent.pathDisplay,
                lastOpenedAt: recent.lastOpenedAt
            )
        )
    }

    private func beginChecking(_ url: URL) {
        checkState = .checking(url.path)
        error = nil
        route = nil
        shareImportTakeoverConnection = nil
        latestValidation = nil
        latestCloudState = nil
    }

    private func routeValidatedRepository(_ validation: MobileRepositoryValidation, sourceURL: URL) async throws {
        latestValidation = validation
        if let blockingError = Self.blockingError(for: validation) {
            applyFailure(blockingError)
            return
        }
        let cloudState: MobileCloudStorageState
        do {
            cloudState = try await bridge.detectCloudStorageState(repoPath: validation.repoPath)
        } catch {
            let failure = Self.connectionError(from: error)
            if Self.shouldRouteCloudDetectionFailure(failure, validation: validation) {
                applyCloudFailure(failure)
                return
            }
            throw error
        }
        latestCloudState = cloudState
        if let cloudError = Self.cloudBlockingError(for: cloudState) {
            applyCloudFailure(cloudError)
            return
        }
        if validation.isInitialized {
            let bookmark = try await accessService.persistBookmark(for: sourceURL, lastOpenedAt: now())
            try await openExistingRepository(validation, bookmark: bookmark)
            return
        }
        let bookmark = Self.candidateBookmark(for: sourceURL, lastOpenedAt: now())
        routeUninitializedRepository(validation, bookmark: bookmark)
    }

    private func openExistingRepository(
        _ validation: MobileRepositoryValidation,
        bookmark: RepositoryBookmark
    ) async throws {
        let config = try await bridge.loadConfig(repoPath: validation.repoPath)
        checkState = .idle
        route = .mobileLibrary(MobileRepositoryConnection(
            validation: validation,
            config: config,
            bookmark: bookmark
        ))
    }

    private func routeUninitializedRepository(
        _ validation: MobileRepositoryValidation,
        bookmark: RepositoryBookmark
    ) {
        checkState = .idle
        let candidate = MobileRepositoryCandidate(validation: validation, bookmark: bookmark)
        switch validation.recommendedMode {
        case .createEmpty:
            route = .repositoryInitConfirm(candidate)
        case .adoptExisting:
            route = .repositoryAdoptConfirm(candidate)
        case nil:
            applyFailure(.invalidRepository(validation.repoPath))
        }
    }

    private func applyFailure(_ failure: MobileRepositoryConnectionError) {
        checkState = .idle
        error = failure
        if Self.shouldRouteToICloudPermission(failure) {
            route = .iCloudPermission(failure)
        }
    }

    private func applyCloudFailure(_ failure: MobileRepositoryConnectionError) {
        checkState = .idle
        error = failure
        route = .iCloudPermission(failure)
    }

    private static func blockingError(for validation: MobileRepositoryValidation) -> MobileRepositoryConnectionError? {
        if validation.isInsideAreaMatrix || validation.issues.contains(.insideAreaMatrix) {
            return .invalidPath(validation.repoPath)
        }
        if !validation.exists || validation.issues.contains(.missingPath) {
            return .invalidPath(validation.repoPath)
        }
        if !validation.isDirectory || validation.issues.contains(.notDirectory) {
            return .selectedFile(validation.repoPath)
        }
        if !validation.isReadable || validation.issues.contains(.notReadable) {
            return .permissionDenied(validation.repoPath)
        }
        if validation.issues.contains(.iCloudPath) && validation.isInitialized == false {
            return nil
        }
        if validation.hasUnfinishedScanSession || validation.issues.contains(.unfinishedScanSession) {
            return nil
        }
        if validation.recommendedMode == nil && validation.isInitialized == false {
            return .invalidRepository(validation.repoPath)
        }
        return nil
    }

    private static func cloudBlockingError(
        for state: MobileCloudStorageState
    ) -> MobileRepositoryConnectionError? {
        if state.placeholderState == .placeholder {
            return .iCloudPlaceholder(state.repoPath)
        }
        if state.requiresReconnect || state.recommendedAction == .reconnectFolder {
            return .accessExpired(state.repoPath)
        }
        switch state.permissionState {
        case .accessible:
            return nil
        case .permissionDenied:
            return .permissionDenied(state.repoPath)
        case .accessExpired:
            return .accessExpired(state.repoPath)
        case .unknown:
            if state.providerKind == .iCloudDrive || state.providerKind == .unknown {
                return .unavailable(state.statusSummary)
            }
            return nil
        }
    }

    private static func shouldRouteToICloudPermission(_ failure: MobileRepositoryConnectionError) -> Bool {
        switch failure {
        case .iCloudPlaceholder:
            return true
        case .invalidPath, .selectedFile, .permissionDenied, .accessExpired, .invalidRepository, .unavailable:
            return false
        }
    }

    private static func shouldRouteCloudDetectionFailure(
        _ failure: MobileRepositoryConnectionError,
        validation: MobileRepositoryValidation
    ) -> Bool {
        if case .iCloudPlaceholder = failure {
            return true
        }
        guard validation.isICloudPath
            || validation.issues.contains(.iCloudPath)
            || validation.platformPathKind == .iCloudDrive else {
            return false
        }
        switch failure {
        case .permissionDenied, .accessExpired, .unavailable:
            return true
        case .invalidPath, .selectedFile, .iCloudPlaceholder, .invalidRepository:
            return false
        }
    }

    private static func candidateBookmark(for url: URL, lastOpenedAt: Date) -> RepositoryBookmark {
        RepositoryBookmark(
            url: url,
            displayName: url.lastPathComponent.isEmpty ? "Repository" : url.lastPathComponent,
            pathDisplay: url.path,
            lastOpenedAt: lastOpenedAt
        )
    }

    private static func connectionError(from error: Error) -> MobileRepositoryConnectionError {
        if let failure = error as? MobileRepositoryConnectionError {
            return failure
        }
        return .unavailable(error.localizedDescription)
    }
}
