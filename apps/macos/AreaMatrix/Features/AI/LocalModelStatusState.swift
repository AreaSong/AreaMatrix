import Foundation

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

extension LocalModelAvailabilityState {
    // swiftlint:disable:next cyclomatic_complexity
    init(coreAvailability: LocalModelAvailability) {
        switch coreAvailability {
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

extension LocalModelRecommendedActionState {
    init(coreAction: LocalModelRecommendedAction) {
        switch coreAction {
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
