import Foundation

protocol MobileRepositoryCoreBridge: Sendable {
    func validateRepoPath(repoPath: String) async throws -> MobileRepositoryValidation
    func detectCloudStorageState(repoPath: String) async throws -> MobileCloudStorageState
    func initializeEmptyRepository(repoPath: String) async throws
    func adoptExistingRepository(repoPath: String) async throws
    func loadConfig(repoPath: String) async throws -> MobileRepositoryConfig
}

enum MobileRepositoryInitMode: String, Equatable, Sendable {
    case createEmpty = "CreateEmpty"
    case adoptExisting = "AdoptExisting"
}

enum MobileRepositoryPathIssue: String, Equatable, Sendable {
    case missingPath = "MissingPath"
    case notDirectory = "NotDirectory"
    case notReadable = "NotReadable"
    case notWritable = "NotWritable"
    case nonEmptyDirectory = "NonEmptyDirectory"
    case alreadyInitialized = "AlreadyInitialized"
    case insideAreaMatrix = "InsideAreaMatrix"
    case iCloudPath = "ICloudPath"
    case oneDrivePath = "OneDrivePath"
    case windowsReservedName = "WindowsReservedName"
    case windowsCaseInsensitive = "WindowsCaseInsensitive"
    case unfinishedScanSession = "UnfinishedScanSession"
}

enum MobileRepositoryPlatformPathKind: String, Equatable, Sendable {
    case local = "Local"
    case iCloudDrive = "ICloudDrive"
    case oneDrive = "OneDrive"
    case networkShare = "NetworkShare"
    case unknown = "Unknown"
}

struct MobileRepositoryValidation: Equatable, Sendable {
    var repoPath: String
    var exists: Bool
    var isDirectory: Bool
    var isReadable: Bool
    var isWritable: Bool
    var isEmpty: Bool
    var isInitialized: Bool
    var isInsideAreaMatrix: Bool
    var isICloudPath: Bool
    var isOneDrivePath: Bool
    var platformPathKind: MobileRepositoryPlatformPathKind
    var isCaseSensitivePath: Bool
    var hasUnfinishedScanSession: Bool
    var recommendedMode: MobileRepositoryInitMode?
    var issues: [MobileRepositoryPathIssue]

    var isThirdPartyCloudPath: Bool {
        isOneDrivePath
            || issues.contains(.oneDrivePath)
            || platformPathKind == .oneDrive
            || isKnownThirdPartyCloudPath
    }

    private var isKnownThirdPartyCloudPath: Bool {
        let lowered = repoPath.lowercased()
        return lowered.contains("/dropbox/")
            || lowered.contains("/google drive/")
            || lowered.contains("/box/")
    }
}

struct MobileRepositoryConfig: Equatable, Sendable {
    var repoPath: String
    var defaultMode: String
    var locale: String
    var allowReplaceDuringImport = false
}

struct MobileRepositoryConnection: Equatable, Sendable {
    var validation: MobileRepositoryValidation
    var config: MobileRepositoryConfig
    var bookmark: RepositoryBookmark
}

struct MobileRepositoryCandidate: Equatable, Sendable {
    var validation: MobileRepositoryValidation
    var bookmark: RepositoryBookmark
}

enum MobileRepositoryConnectionRoute: Equatable, Sendable {
    case mobileLibrary(MobileRepositoryConnection)
    case repositoryInitConfirm(MobileRepositoryCandidate)
    case repositoryAdoptConfirm(MobileRepositoryCandidate)
    case iCloudPermission(MobileRepositoryConnectionError)
}

enum MobileRepositoryConnectionError: Error, Equatable, Sendable {
    case invalidPath(String)
    case selectedFile(String)
    case permissionDenied(String)
    case accessExpired(String)
    case iCloudPlaceholder(String)
    case invalidRepository(String)
    case unavailable(String)

    var message: String {
        switch self {
        case .invalidPath:
            "请选择可访问的资料库文件夹。"
        case .selectedFile:
            "请选择资料库文件夹，而不是单个文件。"
        case .permissionDenied:
            "AreaMatrix 没有访问该文件夹的权限，请重新授权。"
        case .accessExpired:
            "该资料库访问凭证已失效，请重新连接。"
        case .iCloudPlaceholder:
            "该资料库仍是 iCloud 占位状态，请先在 Files 中下载后重试。"
        case .invalidRepository:
            "该文件夹不是可连接的 AreaMatrix 资料库。"
        case let .unavailable(message):
            message
        }
    }
}
