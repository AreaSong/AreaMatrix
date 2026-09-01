import Combine

@MainActor
public final class MainSelectionModel: ObservableObject {
    @Published public var fileIDs: Set<Int64> = []
    @Published public var pendingMovedFileFocusID: Int64?

    public init() {}
}
