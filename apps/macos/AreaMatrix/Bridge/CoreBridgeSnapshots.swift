import AreaMatrixCoreBridgeContract
import Foundation

typealias CoreCommandIndexing = AreaMatrixCoreBridgeContract.CoreCommandIndexing
typealias CommandIndexRequestSnapshot = AreaMatrixCoreBridgeContract.CommandIndexRequestSnapshot
typealias CoreCommandIndexSnapshot = AreaMatrixCoreBridgeContract.CoreCommandIndexSnapshot
typealias CoreCommandTargetSnapshot = AreaMatrixCoreBridgeContract.CoreCommandTargetSnapshot
typealias CommandTargetGroupSnapshot = AreaMatrixCoreBridgeContract.CommandTargetGroupSnapshot
typealias CommandTargetKindSnapshot = AreaMatrixCoreBridgeContract.CommandTargetKindSnapshot
typealias CommandTargetActionSnapshot = AreaMatrixCoreBridgeContract.CommandTargetActionSnapshot
typealias CoreCategoryPredicting = AreaMatrixCoreBridgeContract.CoreCategoryPredicting
typealias ClassifyReasonSnapshot = AreaMatrixCoreBridgeContract.ClassifyReasonSnapshot
typealias ClassifyResultSnapshot = AreaMatrixCoreBridgeContract.ClassifyResultSnapshot

extension CoreCommandIndexSnapshot {
    init(coreIndex: CommandIndex) {
        self.init(
            commands: coreIndex.commands.map(CoreCommandTargetSnapshot.init(coreTarget:)),
            navigationTargets: coreIndex.navigationTargets.map(CoreCommandTargetSnapshot.init(coreTarget:)),
            currentSelectionTargets: coreIndex.currentSelectionTargets.map(
                CoreCommandTargetSnapshot.init(coreTarget:)
            ),
            recentTargets: coreIndex.recentTargets.map(CoreCommandTargetSnapshot.init(coreTarget:)),
            smartLists: coreIndex.smartLists.map(CoreCommandTargetSnapshot.init(coreTarget:)),
            fileCandidates: coreIndex.fileCandidates.map(CoreCommandTargetSnapshot.init(coreTarget:)),
            generatedAt: coreIndex.generatedAt
        )
    }
}

private extension CoreCommandTargetSnapshot {
    init(coreTarget: CommandTarget) {
        self.init(
            id: coreTarget.id,
            title: coreTarget.title,
            subtitle: coreTarget.subtitle,
            group: CommandTargetGroupSnapshot(coreGroup: coreTarget.group),
            kind: CommandTargetKindSnapshot(coreKind: coreTarget.kind),
            action: CommandTargetActionSnapshot(coreAction: coreTarget.action),
            route: coreTarget.route,
            shortcut: coreTarget.shortcut,
            disabled: coreTarget.disabled,
            disabledReason: coreTarget.disabledReason,
            requiresConfirmation: coreTarget.requiresConfirmation,
            fileID: coreTarget.fileId,
            savedSearchID: coreTarget.savedSearchId
        )
    }
}

private extension CommandTargetGroupSnapshot {
    init(coreGroup: CommandTargetGroup) {
        switch coreGroup {
        case .commands: self = .commands
        case .navigation: self = .navigation
        case .currentSelection: self = .currentSelection
        case .recent: self = .recent
        case .smartLists: self = .smartLists
        case .fileCandidates: self = .fileCandidates
        }
    }
}

private extension CommandTargetKindSnapshot {
    init(coreKind: CommandTargetKind) {
        switch coreKind {
        case .command: self = .command
        case .navigation: self = .navigation
        case .smartList: self = .smartList
        case .fileCandidate: self = .fileCandidate
        case .recentCommand: self = .recentCommand
        }
    }
}

private extension CommandTargetActionSnapshot {
    init(coreAction: CommandTargetAction) {
        switch coreAction {
        case .navigate: self = .navigate
        case .openSheet: self = .openSheet
        case .openConfirmation: self = .openConfirmation
        case .runSmartList: self = .runSmartList
        case .focusFile: self = .focusFile
        case .openSearch: self = .openSearch
        case .lowRiskAction: self = .lowRiskAction
        }
    }
}

extension CommandIndexContext {
    init(snapshot: CommandIndexRequestSnapshot) {
        self.init(
            query: snapshot.query,
            selectedFileIds: snapshot.selectedFileIDs,
            currentPath: snapshot.currentPath,
            includeFileCandidates: snapshot.includeFileCandidates
        )
    }
}

extension ClassifyReasonSnapshot {
    var displayLabel: String {
        switch self {
        case .keyword:
            L10n.string("keyword")
        case .extension:
            L10n.string("extension")
        case .aiPredicted:
            L10n.string("AI")
        case .default:
            L10n.string("default")
        }
    }
}

extension ClassifyResultSnapshot {
    var confidencePercent: Int {
        Int((confidence * 100).rounded())
    }
}

extension ClassifyResultSnapshot {
    init(coreResult: ClassifyResult) {
        self.init(
            category: coreResult.category,
            suggestedName: coreResult.suggestedName,
            reason: ClassifyReasonSnapshot(coreReason: coreResult.reason),
            confidence: coreResult.confidence
        )
    }
}

private extension ClassifyReasonSnapshot {
    init(coreReason: ClassifyReason) {
        switch coreReason {
        case .keyword:
            self = .keyword
        case .extension:
            self = .extension
        case .aiPredicted:
            self = .aiPredicted
        case .default:
            self = .default
        }
    }
}

extension ReindexReportSnapshot {
    init(coreReport: ReindexReport) {
        self.init(
            scanSessionId: coreReport.scanSessionId,
            inserted: coreReport.inserted,
            updated: coreReport.updated,
            skipped: coreReport.skipped,
            errors: coreReport.errors
        )
    }
}

extension ScanSessionSnapshot {
    init(coreSession: ScanSession) {
        self.init(
            id: coreSession.id,
            kind: ScanSessionKindSnapshot(coreKind: coreSession.kind),
            status: ScanSessionStatusSnapshot(coreStatus: coreSession.status),
            lastPath: coreSession.lastPath,
            inserted: coreSession.inserted,
            updated: coreSession.updated,
            skipped: coreSession.skipped,
            startedAt: coreSession.startedAt,
            updatedAt: coreSession.updatedAt,
            finishedAt: coreSession.finishedAt,
            errors: coreSession.errors
        )
    }
}

private extension ScanSessionKindSnapshot {
    init(coreKind: ScanSessionKind) {
        switch coreKind {
        case .adopt:
            self = .adopt
        case .reindex:
            self = .reindex
        }
    }
}

private extension ScanSessionStatusSnapshot {
    init(coreStatus: ScanSessionStatus) {
        switch coreStatus {
        case .running:
            self = .running
        case .completed:
            self = .completed
        case .paused:
            self = .paused
        case .failed:
            self = .failed
        case .interrupted:
            self = .interrupted
        }
    }
}

extension RepoPathValidationSnapshot {
    init(coreValidation: RepoPathValidation) {
        let environment = RepositoryPathEnvironmentSnapshot.inspect(repoPath: coreValidation.repoPath)

        self.init(
            repoPath: coreValidation.repoPath,
            exists: coreValidation.exists,
            isDirectory: coreValidation.isDirectory,
            isReadable: coreValidation.isReadable,
            isWritable: coreValidation.isWritable,
            isEmpty: coreValidation.isEmpty,
            isInitialized: coreValidation.isInitialized,
            isInsideAreaMatrix: coreValidation.isInsideAreaMatrix,
            isICloudPath: coreValidation.isIcloudPath,
            hasUnfinishedScanSession: coreValidation.hasUnfinishedScanSession,
            availableCapacityBytes: environment.availableCapacityBytes,
            isExternalVolume: environment.isExternalVolume,
            recommendedMode: coreValidation.recommendedMode.map(RepoInitModeSnapshot.init(coreMode:)),
            issues: coreValidation.issues.map(RepoPathIssueSnapshot.init(coreIssue:))
        )
    }
}

private struct RepositoryPathEnvironmentSnapshot {
    var availableCapacityBytes: Int64?
    var isExternalVolume: Bool?

    static func inspect(repoPath: String) -> RepositoryPathEnvironmentSnapshot {
        do {
            let keys: Set<URLResourceKey> = [
                .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey, .volumeIsInternalKey
            ]
            let values = try URL(fileURLWithPath: repoPath).resourceValues(forKeys: keys)
            return RepositoryPathEnvironmentSnapshot(
                availableCapacityBytes: values.volumeAvailableCapacityForImportantUsage ??
                    values.volumeAvailableCapacity.map(Int64.init),
                isExternalVolume: values.volumeIsInternal.map { !$0 }
            )
        } catch {
            return RepositoryPathEnvironmentSnapshot(availableCapacityBytes: nil, isExternalVolume: nil)
        }
    }
}

private extension RepoInitModeSnapshot {
    init(coreMode: RepoInitMode) {
        switch coreMode {
        case .createEmpty:
            self = .createEmpty
        case .adoptExisting:
            self = .adoptExisting
        }
    }
}

private extension RepoPathIssueSnapshot {
    // swiftlint:disable:next cyclomatic_complexity
    init(coreIssue: RepoPathIssue) {
        switch coreIssue {
        case .missingPath:
            self = .missingPath
        case .notDirectory:
            self = .notDirectory
        case .notReadable:
            self = .notReadable
        case .notWritable:
            self = .notWritable
        case .nonEmptyDirectory:
            self = .nonEmptyDirectory
        case .alreadyInitialized:
            self = .alreadyInitialized
        case .insideAreaMatrix:
            self = .insideAreaMatrix
        case .iCloudPath:
            self = .iCloudPath
        case .oneDrivePath:
            self = .oneDrivePath
        case .windowsReservedName:
            self = .windowsReservedName
        case .windowsCaseInsensitive:
            self = .windowsCaseInsensitive
        case .unfinishedScanSession:
            self = .unfinishedScanSession
        }
    }
}

protocol CoreLocalModelStatusReading: Sendable {
    func getLocalModelStatus(
        repoPath: String,
        request: LocalModelStatusRequestState
    ) async throws -> LocalModelStatusState
    func locateLocalModelFolder(
        repoPath: String,
        request: LocalModelFolderRequestState
    ) async throws -> LocalModelFolderLocationState
}

enum LocalModelAvailabilityState: String, Equatable {
    case unknown, ready, notInstalled, pathUnreadable, versionIncompatible
    case checking, verifying, loading, corrupted, runtimeFailed, error

    var isBusy: Bool {
        self == .checking || self == .verifying || self == .loading
    }
}

enum LocalModelRecommendedActionState: String, Equatable {
    case none, checkStatus, retryStatusCheck, openInstallHelp, openModelLocation
    case runHealthCheck, repairMetadata, openDiagnostics, useNonAiFallback
}

struct LocalModelFeatureStatusState: Equatable, Identifiable {
    var feature: AISettingsFeatureKind
    var available: Bool
    var unavailableReason: String?

    var id: String {
        feature.rawValue
    }
}

struct LocalModelCachedStatusState: Equatable {
    var modelID: String
    var storageLocation: String
    var availability: LocalModelAvailabilityState
    var version: String?
    var sizeBytes: Int64?
    var lastError: String?
    var recommendedAction: LocalModelRecommendedActionState
    var lastCheckedAt: Int64?
    var diagnosticsSummary: String
}
