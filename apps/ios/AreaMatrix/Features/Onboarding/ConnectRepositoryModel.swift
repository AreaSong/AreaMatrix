import Foundation

@MainActor
final class ConnectRepositoryModel: ObservableObject {
    enum CheckState: Equatable {
        case idle
        case checking(String)
        case creating(String)
    }

    @Published private(set) var checkState: CheckState = .idle
    @Published private(set) var recentRepositories: [RecentRepository] = []
    @Published private(set) var error: MobileRepositoryConnectionError?
    @Published private(set) var route: MobileRepositoryConnectionRoute?
    @Published private(set) var latestValidation: MobileRepositoryValidation?
    @Published private(set) var latestCloudState: MobileCloudStorageState?
    @Published private(set) var shareImportTakeoverConnection: MobileRepositoryConnection?
    private var activeRequestID: UUID?

    let bridge: any MobileRepositoryCoreBridge
    let accessService: any RepositoryAccessServicing
    let now: @Sendable () -> Date

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
        switch checkState {
        case .checking, .creating:
            true
        case .idle:
            false
        }
    }

    var isCreatingRepository: Bool {
        if case .creating = checkState { return true }
        return false
    }

    func loadRecentRepositories() async {
        recentRepositories = await accessService.recentRepositories()
    }

    @discardableResult
    func connectICloudRepository() async -> Bool {
        prepareForPicker()
        let requestID = UUID()
        activeRequestID = requestID
        guard await accessService.isICloudDriveAvailable() else {
            guard activeRequestID == requestID, !Task.isCancelled else { return false }
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
        let requestID = UUID()
        activeRequestID = requestID
        do {
            let url = try await accessService.resolveBookmark(for: recent)
            guard activeRequestID == requestID, !Task.isCancelled else { return false }
            await connect(url: url)
            return false
        } catch {
            guard activeRequestID == requestID, !Task.isCancelled else { return false }
            applyFailure(.accessExpired(recent.pathDisplay))
            return true
        }
    }

    func cancelSystemPicker() {
        activeRequestID = nil
        checkState = .idle
    }

    func dismissRoute() {
        route = nil
    }

    @discardableResult
    func retryICloudPermissionCheck() async -> Bool {
        guard let validation = latestValidation else {
            return await connectICloudRepository()
        }
        await connect(url: URL(fileURLWithPath: validation.repoPath, isDirectory: true))
        return false
    }

    func beginRecoveryFolderSelection() {
        prepareForPicker()
    }

    func handleOpenURL(_ url: URL) async {
        guard url.scheme == "areamatrix", url.host == "share-import" else { return }
        await openRecentRepositoryForShareImport()
    }

    private func openRecentRepositoryForShareImport() async {
        let requestID = UUID()
        activeRequestID = requestID
        let repositories = await accessService.recentRepositories()
        guard activeRequestID == requestID, !Task.isCancelled else { return }
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
            guard activeRequestID == requestID, !Task.isCancelled else { return }
            try await routeShareImportRepository(url: url, recent: recent, requestID: requestID)
        } catch {
            guard activeRequestID == requestID, !Task.isCancelled else { return }
            applyFailure(Self.connectionError(from: error))
        }
    }

    private func prepareForPicker() {
        activeRequestID = nil
        checkState = .idle
        error = nil
        route = nil
        latestValidation = nil
        latestCloudState = nil
        shareImportTakeoverConnection = nil
    }

    private func connect(url: URL) async {
        let requestID = UUID()
        activeRequestID = requestID
        guard url.isFileURL else {
            applyFailure(.invalidPath(url.absoluteString))
            return
        }
        shareImportTakeoverConnection = nil
        beginChecking(url)
        do {
            let scopedAccess = try await accessService.beginAccessing(url)
            let validation = try await bridge.validateRepoPath(repoPath: url.path)
            guard activeRequestID == requestID, !Task.isCancelled else { return }
            try await routeValidatedRepository(
                validation,
                sourceURL: url,
                scopedAccess: scopedAccess,
                requestID: requestID
            )
        } catch {
            guard activeRequestID == requestID, !Task.isCancelled else { return }
            applyFailure(Self.connectionError(from: error))
        }
    }

    private func routeShareImportRepository(
        url: URL,
        recent: RecentRepository,
        requestID: UUID
    ) async throws {
        guard url.isFileURL else {
            applyFailure(.invalidPath(url.absoluteString))
            return
        }
        beginChecking(url)
        let scopedAccess = try await accessService.beginAccessing(url)
        let validation = try await bridge.validateRepoPath(repoPath: url.path)
        guard activeRequestID == requestID, !Task.isCancelled else { return }
        if let blockingError = Self.blockingError(for: validation) {
            applyFailure(blockingError)
            return
        }
        let config = try await bridge.loadConfig(repoPath: validation.repoPath)
        guard activeRequestID == requestID, !Task.isCancelled else { return }
        checkState = .idle
        shareImportTakeoverConnection = MobileRepositoryConnection(
            validation: validation,
            config: config,
            bookmark: RepositoryBookmark(
                url: url,
                displayName: recent.displayName,
                pathDisplay: recent.pathDisplay,
                lastOpenedAt: recent.lastOpenedAt
            ),
            scopedAccess: scopedAccess
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

    private func routeValidatedRepository(
        _ validation: MobileRepositoryValidation,
        sourceURL: URL,
        scopedAccess: RepositoryScopedAccess,
        requestID: UUID
    ) async throws {
        guard activeRequestID == requestID, !Task.isCancelled else { return }
        latestValidation = validation
        if let blockingError = Self.blockingError(for: validation) {
            applyFailure(blockingError)
            return
        }
        let cloudState: MobileCloudStorageState
        do {
            cloudState = try await bridge.detectCloudStorageState(repoPath: validation.repoPath)
            guard activeRequestID == requestID, !Task.isCancelled else { return }
        } catch {
            let failure = Self.connectionError(from: error)
            guard activeRequestID == requestID, !Task.isCancelled else { return }
            if Self.shouldRouteCloudDetectionFailure(failure, validation: validation) {
                applyCloudFailure(failure)
                return
            }
            throw error
        }
        latestCloudState = cloudState
        guard activeRequestID == requestID, !Task.isCancelled else { return }
        if let cloudError = Self.cloudBlockingError(for: cloudState) {
            applyCloudFailure(cloudError)
            return
        }
        if validation.isInitialized {
            let bookmark = try await accessService.persistBookmark(for: sourceURL, lastOpenedAt: now())
            guard activeRequestID == requestID, !Task.isCancelled else { return }
            try await openExistingRepository(
                validation,
                bookmark: bookmark,
                scopedAccess: scopedAccess,
                requestID: requestID
            )
            return
        }
        let bookmark = Self.candidateBookmark(for: sourceURL, lastOpenedAt: now())
        routeUninitializedRepository(
            validation,
            bookmark: bookmark,
            scopedAccess: scopedAccess
        )
    }

    private func openExistingRepository(
        _ validation: MobileRepositoryValidation,
        bookmark: RepositoryBookmark,
        scopedAccess: RepositoryScopedAccess,
        requestID: UUID
    ) async throws {
        let config = try await bridge.loadConfig(repoPath: validation.repoPath)
        guard activeRequestID == requestID, !Task.isCancelled else { return }
        checkState = .idle
        route = .mobileLibrary(MobileRepositoryConnection(
            validation: validation,
            config: config,
            bookmark: bookmark,
            scopedAccess: scopedAccess
        ))
    }

    func openCreatedRepository(
        validation: MobileRepositoryValidation,
        bookmark: RepositoryBookmark,
        scopedAccess: RepositoryScopedAccess
    ) async throws {
        let config = try await bridge.loadConfig(repoPath: validation.repoPath)
        checkState = .idle
        route = .mobileLibrary(MobileRepositoryConnection(
            validation: validation,
            config: config,
            bookmark: bookmark,
            scopedAccess: scopedAccess
        ))
    }

    func beginRepositoryConfirmation(
        _ candidate: MobileRepositoryCandidate,
        route: MobileRepositoryConnectionRoute,
        state: CheckState
    ) {
        checkState = state
        error = nil
        self.route = route
        latestValidation = candidate.validation
    }

    func applyRefreshedRepositoryCandidate(
        _ candidate: MobileRepositoryCandidate,
        route: MobileRepositoryConnectionRoute
    ) {
        latestValidation = candidate.validation
        self.route = route
        checkState = .idle
    }

    func restoreRepositoryConfirmationRoute(_ route: MobileRepositoryConnectionRoute) {
        self.route = route
    }

    func recordLatestValidation(_ validation: MobileRepositoryValidation) {
        latestValidation = validation
    }

    private func routeUninitializedRepository(
        _ validation: MobileRepositoryValidation,
        bookmark: RepositoryBookmark,
        scopedAccess: RepositoryScopedAccess
    ) {
        checkState = .idle
        let candidate = MobileRepositoryCandidate(
            validation: validation,
            bookmark: bookmark,
            scopedAccess: scopedAccess
        )
        switch validation.recommendedMode {
        case .createEmpty:
            route = .repositoryInitConfirm(candidate)
        case .adoptExisting:
            route = .repositoryAdoptConfirm(candidate)
        case nil:
            applyFailure(.invalidRepository(validation.repoPath))
        }
    }

    func applyFailure(_ failure: MobileRepositoryConnectionError) {
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
        if (!validation.exists || validation.issues.contains(.missingPath))
            && validation.recommendedMode != .createEmpty {
            return .invalidPath(validation.repoPath)
        }
        if !validation.exists && validation.recommendedMode == .createEmpty {
            return nil
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
        if validation.recommendedMode == nil, validation.isInitialized == false {
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
                return .unavailable("Cloud storage status is unavailable. Try again.")
            }
            return nil
        }
    }

    private static func shouldRouteToICloudPermission(_ failure: MobileRepositoryConnectionError) -> Bool {
        switch failure {
        case .iCloudPlaceholder:
            true
        case .invalidPath, .selectedFile, .permissionDenied, .accessExpired, .invalidRepository, .unavailable:
            false
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

    static func connectionError(from error: Error) -> MobileRepositoryConnectionError {
        if let failure = error as? MobileRepositoryConnectionError {
            return failure
        }
        return .unavailable("The repository could not be opened. Try again or choose another folder.")
    }
}
