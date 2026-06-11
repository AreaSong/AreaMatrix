import Foundation

struct ICloudConflictApplyContext {
    var fileID: Int64
    var result: ICloudConflictApplyResult
    var originalPath: String?
    var conflictedCopyPath: String?
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
