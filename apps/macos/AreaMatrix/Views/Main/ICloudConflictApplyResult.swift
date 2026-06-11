import Foundation

struct ICloudConflictApplyResult {
    var strategy: ICloudConflictResolutionStrategy
    var report: ICloudConflictResolveReportSnapshot?
    var failure: CoreErrorMappingSnapshot?
}

struct LocalModelStatusRequestState: Equatable {
    var modelID: String
    var storageLocation: String
    var cachedStatus: LocalModelCachedStatusState?
}

struct LocalModelStatusState: Equatable {
    var modelID: String
    var storageLocation: String
    var availability: LocalModelAvailabilityState
    var version: String?
    var sizeBytes: Int64?
    var lastError: String?
    var recommendedAction: LocalModelRecommendedActionState
    var lastCheckedAt: Int64?
    var diagnosticsSummary: String
    var featureStatuses: [LocalModelFeatureStatusState]

    var cachedStatus: LocalModelCachedStatusState {
        LocalModelCachedStatusState(
            modelID: modelID,
            storageLocation: storageLocation,
            availability: availability,
            version: version,
            sizeBytes: sizeBytes,
            lastError: lastError,
            recommendedAction: recommendedAction,
            lastCheckedAt: lastCheckedAt,
            diagnosticsSummary: diagnosticsSummary
        )
    }
}

struct LocalModelFolderRequestState: Equatable {
    var modelID: String
    var storageLocation: String
}

struct LocalModelFolderLocationState: Equatable {
    var modelID: String
    var folderPath: String
    var exists: Bool
    var readable: Bool
    var openable: Bool
    var unavailableReason: String?
}
