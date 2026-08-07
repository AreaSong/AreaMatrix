import AreaMatrixCoreBridgeContract
import Foundation

enum MainRepoDiagnosticsState: Equatable {
    case idle
    case confirmingPrivacy
    case collecting
    case collected(DiagnosticsSnapshotSnapshot)
    case failed(CoreErrorMappingSnapshot)
}
