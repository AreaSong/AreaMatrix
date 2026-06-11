import Foundation

protocol CoreMetadataRepairing: Sendable {
    func repairMetadata(repoPath: String, options: RepairOptionsSnapshot) async throws -> RepairReportSnapshot
}

struct RepairOptionsSnapshot: Equatable {
    var fullRescan: Bool
    var preserveDiagnosticsSnapshot: Bool
}

struct RepairReportSnapshot: Equatable {
    var scanSessionId: Int64?
    var diagnosticsSnapshotPath: String?
    var inserted: Int64
    var updated: Int64
    var skipped: Int64
    var errors: [String]
}

extension RepairReportSnapshot {
    init(coreReport: RepairReport) {
        scanSessionId = coreReport.scanSessionId
        diagnosticsSnapshotPath = coreReport.diagnosticsSnapshotPath
        inserted = coreReport.inserted
        updated = coreReport.updated
        skipped = coreReport.skipped
        errors = coreReport.errors
    }

    var summaryText: String {
        "Inserted \(inserted), updated \(updated), skipped \(skipped)."
    }
}

extension CoreBridge: CoreMetadataRepairing {
    func repairMetadata(repoPath: String, options: RepairOptionsSnapshot) async throws -> RepairReportSnapshot {
        try await Task.detached(priority: .userInitiated) {
            let coreOptions = RepairOptions(
                fullRescan: options.fullRescan,
                preserveDiagnosticsSnapshot: options.preserveDiagnosticsSnapshot
            )
            return try RepairReportSnapshot(coreReport: repairCoreMetadata(repoPath: repoPath, options: coreOptions))
        }.value
    }
}

extension CoreBridge: CoreLocalModelStatusReading {
    func getLocalModelStatus(
        repoPath: String,
        request: LocalModelStatusRequestState
    ) async throws -> LocalModelStatusState {
        try await Task.detached(priority: .userInitiated) {
            try LocalModelStatusState(coreSnapshot: getCoreLocalModelStatus(
                repoPath: repoPath,
                request: LocalModelStatusRequest(snapshot: request)
            ))
        }.value
    }

    func locateLocalModelFolder(
        repoPath: String,
        request: LocalModelFolderRequestState
    ) async throws -> LocalModelFolderLocationState {
        try await Task.detached(priority: .userInitiated) {
            try LocalModelFolderLocationState(coreLocation: getCoreLocalModelFolder(
                repoPath: repoPath,
                request: LocalModelFolderRequest(snapshot: request)
            ))
        }.value
    }
}

private func repairCoreMetadata(repoPath: String, options: RepairOptions) throws -> RepairReport {
    try repairMetadata(repoPath: repoPath, options: options)
}

private func getCoreLocalModelStatus(
    repoPath: String,
    request: LocalModelStatusRequest
) throws -> LocalModelStatusSnapshot {
    try getLocalModelStatus(repoPath: repoPath, request: request)
}

private func getCoreLocalModelFolder(
    repoPath: String,
    request: LocalModelFolderRequest
) throws -> LocalModelFolderLocation {
    try locateLocalModelFolder(repoPath: repoPath, request: request)
}

extension LocalModelStatusState {
    init(coreSnapshot: LocalModelStatusSnapshot) {
        modelID = coreSnapshot.modelId
        storageLocation = coreSnapshot.storageLocation
        availability = LocalModelAvailabilityState(coreAvailability: coreSnapshot.availability)
        version = coreSnapshot.version
        sizeBytes = coreSnapshot.sizeBytes
        lastError = coreSnapshot.lastError
        recommendedAction = LocalModelRecommendedActionState(coreAction: coreSnapshot.recommendedAction)
        lastCheckedAt = coreSnapshot.lastCheckedAt
        diagnosticsSummary = coreSnapshot.diagnosticsSummary
        featureStatuses = coreSnapshot.featureStatuses.map(LocalModelFeatureStatusState.init(coreStatus:))
    }
}

extension LocalModelStatusRequest {
    init(snapshot: LocalModelStatusRequestState) {
        self.init(
            modelId: snapshot.modelID,
            storageLocation: snapshot.storageLocation,
            cachedStatus: snapshot.cachedStatus.map(LocalModelCachedStatus.init(snapshot:))
        )
    }
}

extension LocalModelFolderRequest {
    init(snapshot: LocalModelFolderRequestState) {
        self.init(modelId: snapshot.modelID, storageLocation: snapshot.storageLocation)
    }
}

private extension LocalModelFeatureStatusState {
    init(coreStatus: LocalModelFeatureStatus) {
        feature = AISettingsFeatureKind(coreFeature: coreStatus.feature)
        available = coreStatus.available
        unavailableReason = coreStatus.unavailableReason
    }
}

private extension LocalModelCachedStatus {
    init(snapshot: LocalModelCachedStatusState) {
        self.init(
            modelId: snapshot.modelID,
            storageLocation: snapshot.storageLocation,
            availability: LocalModelAvailability(snapshotAvailability: snapshot.availability),
            version: snapshot.version,
            sizeBytes: snapshot.sizeBytes,
            lastError: snapshot.lastError,
            recommendedAction: LocalModelRecommendedAction(snapshotAction: snapshot.recommendedAction),
            lastCheckedAt: snapshot.lastCheckedAt,
            diagnosticsSummary: snapshot.diagnosticsSummary
        )
    }
}

private extension LocalModelAvailability {
    // swiftlint:disable:next cyclomatic_complexity
    init(snapshotAvailability: LocalModelAvailabilityState) {
        switch snapshotAvailability {
        case .unknown: self = .unknown
        case .ready: self = .ready
        case .notInstalled: self = .notInstalled
        case .pathUnreadable: self = .pathUnreadable
        case .versionIncompatible: self = .versionIncompatible
        case .checking: self = .checking
        case .verifying: self = .verifying
        case .loading: self = .loading
        case .corrupted: self = .corrupted
        case .runtimeFailed: self = .runtimeFailed
        case .error: self = .error
        }
    }
}

private extension LocalModelRecommendedAction {
    init(snapshotAction: LocalModelRecommendedActionState) {
        switch snapshotAction {
        case .none: self = .none
        case .checkStatus: self = .checkStatus
        case .retryStatusCheck: self = .retryStatusCheck
        case .openInstallHelp: self = .openInstallHelp
        case .openModelLocation: self = .openModelLocation
        case .runHealthCheck: self = .runHealthCheck
        case .repairMetadata: self = .repairMetadata
        case .openDiagnostics: self = .openDiagnostics
        case .useNonAiFallback: self = .useNonAiFallback
        }
    }
}

private extension LocalModelFolderLocationState {
    init(coreLocation: LocalModelFolderLocation) {
        modelID = coreLocation.modelId
        folderPath = coreLocation.folderPath
        exists = coreLocation.exists
        readable = coreLocation.readable
        openable = coreLocation.openable
        unavailableReason = coreLocation.unavailableReason
    }
}

extension TagSuggestionApplyReportSnapshot {
    init(coreReport: TagSuggestionApplyReport) {
        fileID = coreReport.fileId
        requestedCount = coreReport.requestedCount
        appliedCount = coreReport.appliedCount
        skippedCount = coreReport.skippedCount
        failedCount = coreReport.failedCount
        itemResults = coreReport.itemResults.map(TagSuggestionApplyItemResultSnapshot.init(coreResult:))
        tagSet = TagSetSnapshot(coreTagSet: coreReport.tagSet)
        undoToken = coreReport.undoToken
        refreshTargets = coreReport.refreshTargets
    }
}

private extension TagSuggestionApplyItemResultSnapshot {
    init(coreResult: TagSuggestionApplyItemResult) {
        suggestionID = coreResult.suggestionId
        slug = coreResult.slug
        status = TagSuggestionApplyStatusSnapshot(coreStatus: coreResult.status)
        error = coreResult.error
    }
}

private extension TagSuggestionApplyStatusSnapshot {
    init(coreStatus: TagSuggestionApplyStatus) {
        switch coreStatus {
        case .applied:
            self = .applied
        case .alreadyAdded:
            self = .alreadyAdded
        case .failed:
            self = .failed
        }
    }
}
