import AreaMatrixCoreBridgeContract
import Foundation

typealias CoreConfigurationLoading = AreaMatrixCoreBridgeContract.CoreConfigurationLoading
typealias CoreConfigurationUpdating = AreaMatrixCoreBridgeContract.CoreConfigurationUpdating
typealias CoreRepositoryPathValidating = AreaMatrixCoreBridgeContract.CoreRepositoryPathValidating
typealias CoreInitializedRepositoryPathValidating =
    AreaMatrixCoreBridgeContract.CoreInitializedRepositoryPathValidating
typealias CoreRepositoryInitializing = AreaMatrixCoreBridgeContract.CoreRepositoryInitializing
typealias CoreScanSessionReading = AreaMatrixCoreBridgeContract.CoreScanSessionReading
typealias RepoInitModeSnapshot = AreaMatrixCoreBridgeContract.RepoInitModeSnapshot
typealias ScanSessionKindSnapshot = AreaMatrixCoreBridgeContract.ScanSessionKindSnapshot
typealias ScanSessionStatusSnapshot = AreaMatrixCoreBridgeContract.ScanSessionStatusSnapshot
typealias RepoPathIssueSnapshot = AreaMatrixCoreBridgeContract.RepoPathIssueSnapshot
typealias RepoPathValidationSnapshot = AreaMatrixCoreBridgeContract.RepoPathValidationSnapshot
typealias RepositoryInitializationDraft = AreaMatrixCoreBridgeContract.RepositoryInitializationDraft
typealias ScanSessionSnapshot = AreaMatrixCoreBridgeContract.ScanSessionSnapshot
typealias ReindexReportSnapshot = AreaMatrixCoreBridgeContract.ReindexReportSnapshot
typealias AppRepoConfigSnapshot = AreaMatrixCoreBridgeContract.AppRepoConfigSnapshot

struct CoreRevisionConflictSnapshot: Equatable {
    var resource: String
    var expectedRevision: Int64
    var currentRevision: Int64

    init?(_ error: Error) {
        guard let coreError = error as? CoreError,
              case let .RevisionConflict(resource, expectedRevision, currentRevision) = coreError
        else { return nil }
        self.resource = resource
        self.expectedRevision = expectedRevision
        self.currentRevision = currentRevision
    }
}

struct CoreConflictSnapshot: Equatable {
    var path: String

    init?(_ error: Error) {
        guard let coreError = error as? CoreError,
              case let .Conflict(path) = coreError
        else { return nil }
        self.path = path
    }
}

extension ContentLocale {
    init(snapshotValue: String) throws {
        switch snapshotValue {
        case "zh-Hans": self = .zhHans
        case "en": self = .en
        default: throw CoreError.Config(reason: "unsupported concrete content locale")
        }
    }

    var snapshotValue: String {
        switch self {
        case .zhHans: "zh-Hans"
        case .en: "en"
        }
    }
}

extension CoreScanSessionReading {
    func resumeScanSession(repoPath _: String, scanSessionId _: Int64) async throws -> ReindexReportSnapshot {
        throw CoreError.Internal(message: "scan session resume is unavailable")
    }
}

extension ScanSessionStatusSnapshot {
    var displayName: String {
        switch self {
        case .running: L10n.string("Running")
        case .completed: L10n.string("Completed")
        case .paused: L10n.string("Paused")
        case .failed: L10n.string("Failed")
        case .interrupted: L10n.string("Interrupted")
        }
    }
}

extension AppRepoConfigSnapshot {
    init(coreConfig: RepoConfigSnapshot) {
        self.init(
            repoPath: coreConfig.repoPath,
            revision: coreConfig.revision,
            defaultMode: coreConfig.defaultMode.displayName,
            overviewOutput: coreConfig.overviewOutput.displayName,
            aiEnabled: coreConfig.aiEnabled,
            locale: coreConfig.localePolicy.rawValue,
            iCloudWarn: coreConfig.icloudWarn,
            enableExtensionRules: coreConfig.enableExtensionRules,
            enableKeywordRules: coreConfig.enableKeywordRules,
            fallbackToInbox: coreConfig.fallbackToInbox,
            allowReplaceDuringImport: coreConfig.allowReplaceDuringImport
        )
    }
}

extension RepositoryLocalePolicy {
    init(snapshotValue: String) throws {
        switch snapshotValue {
        case "system": self = .followInterface
        case "zh-Hans": self = .zhHans
        case "en": self = .en
        default: throw CoreError.Config(reason: "unsupported repository locale policy")
        }
    }
}

extension StorageMode {
    init(snapshotValue: String) throws {
        switch snapshotValue {
        case "Moved":
            self = .moved
        case "Copied":
            self = .copied
        case "Indexed":
            self = .indexed
        default:
            throw CoreError.Config(reason: "unsupported storage mode: \(snapshotValue)")
        }
    }

    var displayName: String {
        switch self {
        case .moved:
            "Moved"
        case .copied:
            "Copied"
        case .indexed:
            "Indexed"
        }
    }
}

extension OverviewOutput {
    init(snapshotValue: String) throws {
        switch snapshotValue {
        case "GeneratedOnly":
            self = .generatedOnly
        case "RootAreaMatrixFile":
            self = .rootAreaMatrixFile
        default:
            throw CoreError.Config(reason: "unsupported overview output: \(snapshotValue)")
        }
    }

    var displayName: String {
        switch self {
        case .generatedOnly:
            "GeneratedOnly"
        case .rootAreaMatrixFile:
            "RootAreaMatrixFile"
        }
    }
}
