@testable import AreaMatrix

extension OnboardingModel {
    var currentImportProgressState: ImportProgressRouteState? {
        guard case let .importProgress(state) = route else { return nil }
        return state
    }
}

actor ImportProgressFatalCopyErrorMapper: CoreErrorMapping {
    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        switch error {
        case .Io: .importProgressFatalCopyError
        default: .importSingleFileError(kind: .internal)
        }
    }
}
