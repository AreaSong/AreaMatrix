import AreaMatrixCoreBridgeContract

/// A MainList-owned selection transition emitted after an external file change.
///
/// Keeping this value contract in the Library target prevents App composition and
/// other feature models from depending on the concrete MainList model.
public enum MainExternalSelectionUpdate: Equatable, Identifiable, Sendable {
    case moved(FileEntrySnapshot)
    case cleared(fileID: Int64)

    public var id: String {
        switch self {
        case let .moved(file):
            "moved:\(file.id):\(file.path)"
        case let .cleared(fileID):
            "cleared:\(fileID)"
        }
    }
}
