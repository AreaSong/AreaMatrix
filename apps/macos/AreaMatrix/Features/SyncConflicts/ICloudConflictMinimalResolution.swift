import Foundation

enum ICloudConflictResolutionStrategy: String, CaseIterable, Equatable, Identifiable {
    case keepBoth
    case keepOriginalOnly
    case keepConflictedCopyOnly

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .keepBoth:
            L10n.string("icloud.conflict.keepBoth")
        case .keepOriginalOnly:
            L10n.string("icloud.conflict.keepOriginal")
        case .keepConflictedCopyOnly:
            L10n.string("icloud.conflict.keepCopy")
        }
    }

    var actionTitle: String {
        switch self {
        case .keepBoth:
            L10n.string("icloud.conflict.apply")
        case .keepOriginalOnly, .keepConflictedCopyOnly:
            L10n.string("icloud.conflict.trashAndApply")
        }
    }

    var runningTitle: String {
        switch self {
        case .keepBoth:
            L10n.string("icloud.conflict.applying")
        case .keepOriginalOnly, .keepConflictedCopyOnly:
            L10n.string("icloud.conflict.movingToTrash")
        }
    }

    var requiresSecondConfirmation: Bool {
        self != .keepBoth
    }

    var successMessage: String {
        switch self {
        case .keepBoth:
            L10n.string("icloud.conflict.keepBothSuccess")
        case .keepOriginalOnly:
            L10n.string("icloud.conflict.keepOriginalSuccess")
        case .keepConflictedCopyOnly:
            L10n.string("icloud.conflict.keepCopySuccess")
        }
    }
}

enum ICloudConflictResolutionState: Equatable {
    case idle
    case applying(fileID: Int64, strategy: ICloudConflictResolutionStrategy)
    case failed(fileID: Int64, strategy: ICloudConflictResolutionStrategy, CoreErrorMappingSnapshot)

    var isApplying: Bool {
        if case .applying = self { return true }
        return false
    }

    func isApplying(fileID: Int64) -> Bool {
        guard case let .applying(applyingFileID, _) = self else { return false }
        return applyingFileID == fileID
    }

    func failedStrategy(fileID: Int64) -> ICloudConflictResolutionStrategy? {
        guard case let .failed(failedFileID, strategy, _) = self,
              failedFileID == fileID else { return nil }
        return strategy
    }

    func failure(fileID: Int64) -> CoreErrorMappingSnapshot? {
        guard case let .failed(failedFileID, _, mapping) = self,
              failedFileID == fileID else { return nil }
        return mapping
    }

    func primaryTitle(
        fileID: Int64,
        selectedStrategy: ICloudConflictResolutionStrategy
    ) -> String {
        if isApplying(fileID: fileID) { return selectedStrategy.runningTitle }
        if failure(fileID: fileID) != nil { return L10n.string("Retry") }
        return selectedStrategy.actionTitle
    }
}

struct ICloudConflictResolutionBlocker: Equatable {
    var title: String
    var message: String
    var suggestedAction: String
    var rawContext: String

    var error: AppSemanticError {
        .internalFailure(rawContext: rawContext)
    }

    static let missingCoreResolutionEndpoint = ICloudConflictResolutionBlocker(
        title: L10n.string("Core resolution unavailable"),
        message: L10n.string("icloud.conflict.resolutionUnavailable.message"),
        suggestedAction: L10n.string("icloud.conflict.resolutionUnavailable.recovery"),
        rawContext: "Missing Core API: resolve_icloud_conflict or mark_icloud_conflict_resolved"
    )
}

enum ICloudConflictResolutionCapability: Equatable {
    case supported
    case blocked(ICloudConflictResolutionBlocker)

    var canResolve: Bool {
        if case .supported = self { return true }
        return false
    }

    var blocker: ICloudConflictResolutionBlocker? {
        guard case let .blocked(blocker) = self else { return nil }
        return blocker
    }
}

struct ICloudConflictResolutionRequest: Equatable {
    var repoPath: String
    var conflictID: String
    /// Token returned by the matching Core preview; empty requests must be rejected by Core.
    var previewToken: String = ""
    var fileID: Int64
    var strategy: ICloudConflictResolutionStrategy
    var originalPath: String?
    var conflictedCopyPath: String?
}

struct ICloudConflictResolutionResult: Equatable {
    var focusFileID: Int64?
    var conflictID: String?
    var report: ICloudConflictResolveReportSnapshot?
    var status: ICloudConflictStatusSnapshot?
    var keptPaths: [String] = []
    var trashedPaths: [String] = []
    var undoToken: String?
    var changeLogAction: String?
    var didClearConflictState: Bool
    var didWriteChangeLog: Bool
}

extension ICloudConflictResolutionResult {
    init(report: ICloudConflictResolveReportSnapshot) {
        focusFileID = nil
        conflictID = report.conflictID
        self.report = report
        status = report.status
        keptPaths = report.keptPaths
        trashedPaths = report.trashedPaths
        undoToken = report.undoToken
        changeLogAction = report.changeLogAction
        didClearConflictState = report.status == .resolved
        didWriteChangeLog = !report.changeLogAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

protocol ICloudConflictResolving: Sendable {
    var iCloudConflictResolutionCapability: ICloudConflictResolutionCapability { get }

    func resolveICloudConflict(_ request: ICloudConflictResolutionRequest) async throws
        -> ICloudConflictResolutionResult
}
