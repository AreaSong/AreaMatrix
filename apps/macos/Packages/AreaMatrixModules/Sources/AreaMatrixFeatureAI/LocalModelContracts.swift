public protocol CoreLocalModelStatusReading: Sendable {
    func getLocalModelStatus(
        repoPath: String,
        request: LocalModelStatusRequestState
    ) async throws -> LocalModelStatusState

    func locateLocalModelFolder(
        repoPath: String,
        request: LocalModelFolderRequestState
    ) async throws -> LocalModelFolderLocationState
}

public enum LocalModelAvailabilityState: String, Equatable, Sendable {
    case unknown, ready, notInstalled, pathUnreadable, versionIncompatible
    case checking, verifying, loading, corrupted, runtimeFailed, error

    public var isBusy: Bool {
        self == .checking || self == .verifying || self == .loading
    }
}

public enum LocalModelRecommendedActionState: String, Equatable, Sendable {
    case none, checkStatus, retryStatusCheck, openInstallHelp, openModelLocation
    case runHealthCheck, repairMetadata, openDiagnostics, useNonAiFallback
}

public struct LocalModelFeatureStatusState: Equatable, Identifiable, Sendable {
    public var feature: AISettingsFeatureKind
    public var available: Bool
    public var unavailableReason: String?

    public init(feature: AISettingsFeatureKind, available: Bool, unavailableReason: String?) {
        self.feature = feature
        self.available = available
        self.unavailableReason = unavailableReason
    }

    public var id: String {
        feature.rawValue
    }
}

public struct LocalModelCachedStatusState: Equatable, Sendable {
    public var modelID: String
    public var storageLocation: String
    public var availability: LocalModelAvailabilityState
    public var version: String?
    public var sizeBytes: Int64?
    public var lastError: String?
    public var recommendedAction: LocalModelRecommendedActionState
    public var lastCheckedAt: Int64?
    public var diagnosticsSummary: String

    public init(
        modelID: String,
        storageLocation: String,
        availability: LocalModelAvailabilityState,
        version: String?,
        sizeBytes: Int64?,
        lastError: String?,
        recommendedAction: LocalModelRecommendedActionState,
        lastCheckedAt: Int64?,
        diagnosticsSummary: String
    ) {
        self.modelID = modelID
        self.storageLocation = storageLocation
        self.availability = availability
        self.version = version
        self.sizeBytes = sizeBytes
        self.lastError = lastError
        self.recommendedAction = recommendedAction
        self.lastCheckedAt = lastCheckedAt
        self.diagnosticsSummary = diagnosticsSummary
    }
}

public struct LocalModelStatusRequestState: Equatable, Sendable {
    public var modelID: String
    public var storageLocation: String
    public var cachedStatus: LocalModelCachedStatusState?

    public init(
        modelID: String,
        storageLocation: String,
        cachedStatus: LocalModelCachedStatusState? = nil
    ) {
        self.modelID = modelID
        self.storageLocation = storageLocation
        self.cachedStatus = cachedStatus
    }
}

public struct LocalModelStatusState: Equatable, Sendable {
    public var modelID: String
    public var storageLocation: String
    public var availability: LocalModelAvailabilityState
    public var version: String?
    public var sizeBytes: Int64?
    public var lastError: String?
    public var recommendedAction: LocalModelRecommendedActionState
    public var lastCheckedAt: Int64?
    public var diagnosticsSummary: String
    public var featureStatuses: [LocalModelFeatureStatusState]

    public init(
        modelID: String,
        storageLocation: String,
        availability: LocalModelAvailabilityState,
        version: String?,
        sizeBytes: Int64?,
        lastError: String?,
        recommendedAction: LocalModelRecommendedActionState,
        lastCheckedAt: Int64?,
        diagnosticsSummary: String,
        featureStatuses: [LocalModelFeatureStatusState]
    ) {
        self.modelID = modelID
        self.storageLocation = storageLocation
        self.availability = availability
        self.version = version
        self.sizeBytes = sizeBytes
        self.lastError = lastError
        self.recommendedAction = recommendedAction
        self.lastCheckedAt = lastCheckedAt
        self.diagnosticsSummary = diagnosticsSummary
        self.featureStatuses = featureStatuses
    }

    public var cachedStatus: LocalModelCachedStatusState {
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

public struct LocalModelFolderRequestState: Equatable, Sendable {
    public var modelID: String
    public var storageLocation: String

    public init(modelID: String, storageLocation: String) {
        self.modelID = modelID
        self.storageLocation = storageLocation
    }
}

public struct LocalModelFolderLocationState: Equatable, Sendable {
    public var modelID: String
    public var folderPath: String
    public var exists: Bool
    public var readable: Bool
    public var openable: Bool
    public var unavailableReason: String?

    public init(
        modelID: String,
        folderPath: String,
        exists: Bool,
        readable: Bool,
        openable: Bool,
        unavailableReason: String?
    ) {
        self.modelID = modelID
        self.folderPath = folderPath
        self.exists = exists
        self.readable = readable
        self.openable = openable
        self.unavailableReason = unavailableReason
    }
}
