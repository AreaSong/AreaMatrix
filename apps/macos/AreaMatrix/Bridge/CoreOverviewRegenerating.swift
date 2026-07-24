import Foundation

protocol CoreOverviewRegenerating: Sendable {
    func overviewLanguageStatus(
        repoPath: String,
        contentLocale: String
    ) async throws -> CoreOverviewLanguageStatusSnapshot

    func prepareOverviewRegeneration(
        repoPath: String,
        contentLocale: String
    ) async throws -> CoreOverviewRegenerationPlanSnapshot

    func startOverviewRegeneration(
        repoPath: String,
        plan: CoreOverviewRegenerationPlanSnapshot
    ) async throws -> CoreOverviewRegenerationSessionSnapshot

    func commitOverviewRegeneration(
        repoPath: String,
        operationID: String
    ) async throws -> CoreOverviewRegenerationSessionSnapshot

    func overviewRegeneration(
        repoPath: String,
        operationID: String
    ) async throws -> CoreOverviewRegenerationSessionSnapshot

    func recoverOverviewRegenerationOnStartup(
        repoPath: String
    ) async throws -> CoreOverviewRegenerationSessionSnapshot?

    func resumeOverviewRegeneration(
        repoPath: String,
        operationID: String
    ) async throws -> CoreOverviewRegenerationSessionSnapshot

    func cancelOverviewRegeneration(
        repoPath: String,
        operationID: String
    ) async throws -> CoreOverviewRegenerationSessionSnapshot

    func rollbackOverviewRegeneration(
        repoPath: String,
        operationID: String
    ) async throws -> CoreOverviewRegenerationSessionSnapshot
}

enum CoreOverviewLanguageStateSnapshot: Equatable {
    case notGenerated
    case synchronized
    case needsRegeneration
    case mixed
    case unknown
}

enum CoreOverviewRegenerationReasonSnapshot: Equatable {
    case localeMismatch
    case formatMismatch
    case missingTargets
    case obsoleteTargets
}

struct CoreOverviewLanguageStatusSnapshot: Equatable {
    var state: CoreOverviewLanguageStateSnapshot
    var contentLocale: String
    var targetCount: Int64
    var knownTargetCount: Int64
    var missingTargetCount: Int64
    var obsoleteTargetCount: Int64
    var knownLocales: [String]
    var knownFormatVersions: [Int64]
    var reasons: [CoreOverviewRegenerationReasonSnapshot]
}

struct CoreOverviewRegenerationPlanSnapshot: Equatable {
    var operationID: String
    var planToken: String
    var repositoryRevision: Int64
    var contentLocale: String
    var formatContractVersion: Int64
    var targetSetHash: String
    var targetCount: Int64
    var createCount: Int64
    var replaceCount: Int64
    var deleteCount: Int64
    var includesRootAreaMatrixFile: Bool
    var warnings: [String]
}

enum CoreOverviewRegenerationStatusSnapshot: Equatable {
    case running
    case staging
    case readyToCommit
    case committing
    case completed
    case rollbackRequired
    case rolledBack
    case failed
    case canceled
}

struct CoreOverviewRegenerationSessionSnapshot: Equatable {
    var operationID: String
    var contentLocale: String?
    var repositoryRevision: Int64
    var formatContractVersion: Int64
    var runSequence: Int64
    var status: CoreOverviewRegenerationStatusSnapshot
    var targetCount: Int64
    var stagedCount: Int64
    var appliedCount: Int64
    var restoredCount: Int64
    var cancellationAllowed: Bool
    var errorCode: String?
    var createdAt: Int64
    var updatedAt: Int64
    var finishedAt: Int64?
}

extension CoreBridge: CoreOverviewRegenerating {
    func overviewLanguageStatus(
        repoPath: String,
        contentLocale: String
    ) async throws -> CoreOverviewLanguageStatusSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try CoreOverviewLanguageStatusSnapshot(coreStatus: getOverviewLanguageStatus(
                repoPath: repoPath,
                contentLocale: ContentLocale(snapshotValue: contentLocale)
            ))
        }.value
    }

    func prepareOverviewRegeneration(
        repoPath: String,
        contentLocale: String
    ) async throws -> CoreOverviewRegenerationPlanSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try CoreOverviewRegenerationPlanSnapshot(corePlan: AreaMatrix.prepareOverviewRegeneration(
                repoPath: repoPath,
                contentLocale: ContentLocale(snapshotValue: contentLocale)
            ))
        }.value
    }

    func startOverviewRegeneration(
        repoPath: String,
        plan: CoreOverviewRegenerationPlanSnapshot
    ) async throws -> CoreOverviewRegenerationSessionSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try CoreOverviewRegenerationSessionSnapshot(coreSession: AreaMatrix.startOverviewRegeneration(
                repoPath: repoPath,
                request: OverviewRegenerationStartRequest(
                    operationId: plan.operationID,
                    planToken: plan.planToken,
                    expectedRepositoryRevision: plan.repositoryRevision,
                    confirmed: true
                )
            ))
        }.value
    }

    func commitOverviewRegeneration(
        repoPath: String,
        operationID: String
    ) async throws -> CoreOverviewRegenerationSessionSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try CoreOverviewRegenerationSessionSnapshot(coreSession: AreaMatrix.commitOverviewRegeneration(
                repoPath: repoPath,
                operationId: operationID
            ))
        }.value
    }

    func overviewRegeneration(
        repoPath: String,
        operationID: String
    ) async throws -> CoreOverviewRegenerationSessionSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try CoreOverviewRegenerationSessionSnapshot(coreSession: AreaMatrix.getOverviewRegeneration(
                repoPath: repoPath,
                operationId: operationID
            ))
        }.value
    }

    func recoverOverviewRegenerationOnStartup(
        repoPath: String
    ) async throws -> CoreOverviewRegenerationSessionSnapshot? {
        try await Task.detached(priority: .userInitiated) {
            try AreaMatrix.recoverOverviewRegenerationOnStartup(repoPath: repoPath)
                .map(CoreOverviewRegenerationSessionSnapshot.init(coreSession:))
        }.value
    }

    func resumeOverviewRegeneration(
        repoPath: String,
        operationID: String
    ) async throws -> CoreOverviewRegenerationSessionSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try CoreOverviewRegenerationSessionSnapshot(coreSession: AreaMatrix.resumeOverviewRegeneration(
                repoPath: repoPath,
                operationId: operationID
            ))
        }.value
    }

    func cancelOverviewRegeneration(
        repoPath: String,
        operationID: String
    ) async throws -> CoreOverviewRegenerationSessionSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try CoreOverviewRegenerationSessionSnapshot(coreSession: AreaMatrix.cancelOverviewRegeneration(
                repoPath: repoPath,
                operationId: operationID
            ))
        }.value
    }

    func rollbackOverviewRegeneration(
        repoPath: String,
        operationID: String
    ) async throws -> CoreOverviewRegenerationSessionSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try CoreOverviewRegenerationSessionSnapshot(coreSession: AreaMatrix.rollbackOverviewRegeneration(
                repoPath: repoPath,
                operationId: operationID
            ))
        }.value
    }
}

private extension CoreOverviewLanguageStatusSnapshot {
    init(coreStatus: OverviewLanguageStatus) {
        state = CoreOverviewLanguageStateSnapshot(coreState: coreStatus.state)
        contentLocale = coreStatus.contentLocale.snapshotValue
        targetCount = coreStatus.targetCount
        knownTargetCount = coreStatus.knownTargetCount
        missingTargetCount = coreStatus.missingTargetCount
        obsoleteTargetCount = coreStatus.obsoleteTargetCount
        knownLocales = coreStatus.knownLocales.map(\.snapshotValue)
        knownFormatVersions = coreStatus.knownFormatVersions
        reasons = coreStatus.reasons.map(CoreOverviewRegenerationReasonSnapshot.init(coreReason:))
    }
}

private extension CoreOverviewRegenerationPlanSnapshot {
    init(corePlan: OverviewRegenerationPlan) {
        operationID = corePlan.operationId
        planToken = corePlan.planToken
        repositoryRevision = corePlan.repositoryRevision
        contentLocale = corePlan.contentLocale.snapshotValue
        formatContractVersion = corePlan.formatContractVersion
        targetSetHash = corePlan.targetSetHash
        targetCount = corePlan.targetCount
        createCount = corePlan.createCount
        replaceCount = corePlan.replaceCount
        deleteCount = corePlan.deleteCount
        includesRootAreaMatrixFile = corePlan.includesRootAreamatrixFile
        warnings = corePlan.warnings
    }
}

private extension CoreOverviewRegenerationSessionSnapshot {
    init(coreSession: OverviewRegenerationSession) {
        operationID = coreSession.context.operationId
        contentLocale = coreSession.context.contentLocale?.snapshotValue
        repositoryRevision = coreSession.context.repositoryRevision
        formatContractVersion = coreSession.context.formatContractVersion
        runSequence = coreSession.context.runSequence
        status = CoreOverviewRegenerationStatusSnapshot(coreStatus: coreSession.status)
        targetCount = coreSession.targetCount
        stagedCount = coreSession.stagedCount
        appliedCount = coreSession.appliedCount
        restoredCount = coreSession.restoredCount
        cancellationAllowed = coreSession.cancellationAllowed
        errorCode = coreSession.errorCode
        createdAt = coreSession.createdAt
        updatedAt = coreSession.updatedAt
        finishedAt = coreSession.finishedAt
    }
}

private extension CoreOverviewLanguageStateSnapshot {
    init(coreState: OverviewLanguageState) {
        switch coreState {
        case .notGenerated: self = .notGenerated
        case .synchronized: self = .synchronized
        case .needsRegeneration: self = .needsRegeneration
        case .mixed: self = .mixed
        case .unknown: self = .unknown
        }
    }
}

private extension CoreOverviewRegenerationReasonSnapshot {
    init(coreReason: OverviewRegenerationReason) {
        switch coreReason {
        case .localeMismatch: self = .localeMismatch
        case .formatMismatch: self = .formatMismatch
        case .missingTargets: self = .missingTargets
        case .obsoleteTargets: self = .obsoleteTargets
        }
    }
}

private extension CoreOverviewRegenerationStatusSnapshot {
    init(coreStatus: OverviewRegenerationStatus) {
        switch coreStatus {
        case .running: self = .running
        case .staging: self = .staging
        case .readyToCommit: self = .readyToCommit
        case .committing: self = .committing
        case .completed: self = .completed
        case .rollbackRequired: self = .rollbackRequired
        case .rolledBack: self = .rolledBack
        case .failed: self = .failed
        case .canceled: self = .canceled
        }
    }
}
