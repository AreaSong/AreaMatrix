import Combine

@MainActor
public final class MainSidebarSelectionModel: ObservableObject {
    @Published public var selectedID: String

    public init(selectedID: String) {
        self.selectedID = selectedID
    }

    @discardableResult
    public func retainSelection(validIDs: Set<String>, fallbackID: String) -> String {
        if !validIDs.contains(selectedID) {
            selectedID = fallbackID
        }
        return selectedID
    }
}
