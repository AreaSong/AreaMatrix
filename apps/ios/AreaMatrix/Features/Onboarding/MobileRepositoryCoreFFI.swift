import AreaMatrixCoreSDK
import Foundation

actor LiveMobileRepositoryCoreBridge: MobileRepositoryCoreBridge {
    private let client: MobileRepositoryCoreFFIClient
    private let cloudClient: MobileCloudStorageCoreFFIClient

    init(
        client: MobileRepositoryCoreFFIClient = MobileRepositoryCoreFFIClient(),
        cloudClient: MobileCloudStorageCoreFFIClient = MobileCloudStorageCoreFFIClient()
    ) {
        self.client = client
        self.cloudClient = cloudClient
    }

    func getVersion() async throws -> String {
        try client.getVersion()
    }

    func validateRepoPath(repoPath: String) async throws -> MobileRepositoryValidation {
        try client.validateRepoPath(repoPath: repoPath)
    }

    func detectCloudStorageState(repoPath: String) async throws -> MobileCloudStorageState {
        try cloudClient.detectCloudStorageState(repoPath: repoPath)
    }

    func initializeEmptyRepository(repoPath: String) async throws {
        try client.initRepo(repoPath: repoPath, mode: .createEmpty, createDefaultCategories: true)
    }

    func adoptExistingRepository(repoPath: String) async throws {
        try client.initRepo(repoPath: repoPath, mode: .adoptExisting, createDefaultCategories: false)
    }

    func loadConfig(repoPath: String) async throws -> MobileRepositoryConfig {
        try client.loadConfig(repoPath: repoPath)
    }

    func updateConfig(repoPath: String, newConfig: MobileRepositoryConfig) async throws {
        try client.updateConfig(repoPath: repoPath, newConfig: newConfig)
    }
}

struct MobileRepositoryCoreFFIClient {
    func getVersion() throws -> String {
        AreaMatrixCoreSDK.getVersion()
    }

    func validateRepoPath(repoPath: String) throws -> MobileRepositoryValidation {
        try withCoreError {
            Self.mapValidation(try AreaMatrixCoreSDK.validateRepoPath(repoPath: repoPath))
        }
    }

    func initRepo(
        repoPath: String,
        mode: MobileRepositoryInitMode,
        createDefaultCategories: Bool
    ) throws {
        let options = AreaMatrixCoreSDK.RepoInitOptions(
            mode: Self.mapInitMode(mode),
            createDefaultCategories: createDefaultCategories,
            overviewOutput: .generatedOnly,
            localePolicy: .followInterface,
            contentLocale: Self.mapContentLocale(MobileRepositoryLocaleSupport.preferredContentLocale())
        )
        try withCoreError {
            try AreaMatrixCoreSDK.initRepo(repoPath: repoPath, options: options)
        }
    }

    func loadConfig(repoPath: String) throws -> MobileRepositoryConfig {
        try withCoreError {
            Self.mapConfig(try AreaMatrixCoreSDK.loadRepoConfig(repoPath: repoPath))
        }
    }

    func updateConfig(repoPath: String, newConfig: MobileRepositoryConfig) throws {
        let patch = try Self.mapConfigPatch(newConfig)
        try withCoreError {
            _ = try AreaMatrixCoreSDK.updateRepoConfig(repoPath: repoPath, patch: patch)
        }
    }

    func contentLocale(repoPath: String) throws -> MobileRepositoryContentLocale {
        try MobileRepositoryLocaleSupport.contentLocale(for: loadConfig(repoPath: repoPath).locale)
    }

    private func withCoreError<T>(_ operation: () throws -> T) throws -> T {
        do {
            return try operation()
        } catch {
            throw Self.mapError(error)
        }
    }

    private static func mapValidation(
        _ value: AreaMatrixCoreSDK.RepoPathValidation
    ) -> MobileRepositoryValidation {
        MobileRepositoryValidation(
            repoPath: value.repoPath,
            exists: value.exists,
            isDirectory: value.isDirectory,
            isReadable: value.isReadable,
            isWritable: value.isWritable,
            isEmpty: value.isEmpty,
            isInitialized: value.isInitialized,
            isInsideAreaMatrix: value.isInsideAreaMatrix,
            isICloudPath: value.isIcloudPath,
            isOneDrivePath: value.isOnedrivePath,
            platformPathKind: mapPlatformPathKind(value.platformPathKind),
            isCaseSensitivePath: value.isCaseSensitivePath,
            hasUnfinishedScanSession: value.hasUnfinishedScanSession,
            recommendedMode: value.recommendedMode.map(mapMobileRepositoryInitMode),
            issues: value.issues.map(mapPathIssue)
        )
    }

    private static func mapConfig(
        _ value: AreaMatrixCoreSDK.RepoConfigSnapshot
    ) -> MobileRepositoryConfig {
        MobileRepositoryConfig(
            repoPath: value.repoPath,
            revision: value.revision,
            defaultMode: mapStorageMode(value.defaultMode),
            overviewOutput: mapOverviewOutput(value.overviewOutput),
            aiEnabled: value.aiEnabled,
            locale: value.localePolicy.rawValue,
            iCloudWarn: value.icloudWarn,
            enableExtensionRules: value.enableExtensionRules,
            enableKeywordRules: value.enableKeywordRules,
            fallbackToInbox: value.fallbackToInbox,
            allowReplaceDuringImport: value.allowReplaceDuringImport
        )
    }

    private static func mapConfigPatch(
        _ value: MobileRepositoryConfig
    ) throws -> AreaMatrixCoreSDK.RepoConfigPatch {
        AreaMatrixCoreSDK.RepoConfigPatch(
            expectedRevision: value.revision,
            repoPath: value.repoPath,
            defaultMode: mapStorageMode(value.defaultMode),
            overviewOutput: mapOverviewOutput(value.overviewOutput),
            aiEnabled: value.aiEnabled,
            localePolicy: try MobileRepositoryLocaleSupport.repositoryLocalePolicy(value.locale),
            icloudWarn: value.iCloudWarn,
            enableExtensionRules: value.enableExtensionRules,
            enableKeywordRules: value.enableKeywordRules,
            fallbackToInbox: value.fallbackToInbox,
            allowReplaceDuringImport: value.allowReplaceDuringImport
        )
    }

    private static func mapInitMode(_ value: MobileRepositoryInitMode) -> AreaMatrixCoreSDK.RepoInitMode {
        switch value {
        case .createEmpty:
            .createEmpty
        case .adoptExisting:
            .adoptExisting
        }
    }

    private static func mapMobileRepositoryInitMode(
        _ value: AreaMatrixCoreSDK.RepoInitMode
    ) -> MobileRepositoryInitMode {
        switch value {
        case .createEmpty:
            .createEmpty
        case .adoptExisting:
            .adoptExisting
        }
    }

    private static func mapContentLocale(
        _ value: MobileRepositoryContentLocale
    ) -> AreaMatrixCoreSDK.ContentLocale {
        switch value {
        case .zhHans:
            .zhHans
        case .en:
            .en
        }
    }

    private static func mapPlatformPathKind(
        _ value: AreaMatrixCoreSDK.PlatformPathKind
    ) -> MobileRepositoryPlatformPathKind {
        switch value {
        case .local:
            .local
        case .iCloudDrive:
            .iCloudDrive
        case .oneDrive:
            .oneDrive
        case .networkShare:
            .networkShare
        case .unknown:
            .unknown
        }
    }

    private static func mapPathIssue(
        _ value: AreaMatrixCoreSDK.RepoPathIssue
    ) -> MobileRepositoryPathIssue {
        switch value {
        case .missingPath:
            .missingPath
        case .notDirectory:
            .notDirectory
        case .notReadable:
            .notReadable
        case .notWritable:
            .notWritable
        case .nonEmptyDirectory:
            .nonEmptyDirectory
        case .alreadyInitialized:
            .alreadyInitialized
        case .insideAreaMatrix:
            .insideAreaMatrix
        case .iCloudPath:
            .iCloudPath
        case .oneDrivePath:
            .oneDrivePath
        case .windowsReservedName:
            .windowsReservedName
        case .windowsCaseInsensitive:
            .windowsCaseInsensitive
        case .unfinishedScanSession:
            .unfinishedScanSession
        }
    }

    private static func mapStorageMode(_ value: AreaMatrixCoreSDK.StorageMode) -> String {
        switch value {
        case .moved:
            "Moved"
        case .copied:
            "Copied"
        case .indexed:
            "Indexed"
        }
    }

    private static func mapStorageMode(_ value: String) -> AreaMatrixCoreSDK.StorageMode {
        switch value {
        case "Moved":
            .moved
        case "Indexed":
            .indexed
        default:
            .copied
        }
    }

    private static func mapOverviewOutput(_ value: AreaMatrixCoreSDK.OverviewOutput) -> String {
        switch value {
        case .generatedOnly:
            "GeneratedOnly"
        case .rootAreaMatrixFile:
            "RootAreaMatrixFile"
        }
    }

    private static func mapOverviewOutput(_ value: String) -> AreaMatrixCoreSDK.OverviewOutput {
        value == "RootAreaMatrixFile" ? .rootAreaMatrixFile : .generatedOnly
    }

    private static func mapError(_ error: Error) -> MobileRepositoryConnectionError {
        guard let coreError = error as? AreaMatrixCoreSDK.CoreError else {
            return (error as? MobileRepositoryConnectionError)
                ?? .unavailable("Repository connection is unavailable. Try again or choose another folder.")
        }
        switch coreError {
        case let .InvalidPath(path):
            return MobileRepositoryConnectionError.invalidPath(path)
        case let .ICloudPlaceholder(path):
            return MobileRepositoryConnectionError.iCloudPlaceholder(path)
        case let .PermissionDenied(path):
            return MobileRepositoryConnectionError.permissionDenied(path)
        case let .RepoNotInitialized(path):
            return MobileRepositoryConnectionError.invalidRepository(path)
        case let .Validation(reason), let .Config(reason):
            return MobileRepositoryConnectionError.invalidRepository(reason)
        default:
            return MobileRepositoryConnectionError.unavailable(
                "Repository connection is unavailable. Try again or choose another folder."
            )
        }
    }
}

enum MobileRepositoryContentLocale: Int32 {
    case zhHans = 1
    case en = 2
}

enum MobileRepositoryLocaleSupport {
    static func preferredContentLocale() -> MobileRepositoryContentLocale {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true ? .zhHans : .en
    }

    static func contentLocale(for policy: String) throws -> MobileRepositoryContentLocale {
        switch policy.lowercased() {
        case "follow-interface", "system":
            preferredContentLocale()
        case "zh-hans":
            .zhHans
        case "en":
            .en
        default:
            throw MobileRepositoryConnectionError.unavailable(
                "Unsupported repository locale policy: \(policy)"
            )
        }
    }

    static func repositoryLocalePolicy(
        _ value: String
    ) throws -> AreaMatrixCoreSDK.RepositoryLocalePolicy {
        switch value.lowercased() {
        case "follow-interface", "system":
            .followInterface
        case "zh-hans":
            .zhHans
        case "en":
            .en
        default:
            throw MobileRepositoryConnectionError.unavailable(
                "Unsupported repository locale policy: \(value)"
            )
        }
    }
}
