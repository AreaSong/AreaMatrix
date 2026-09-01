import SwiftUI

struct ImportConflictBatchRelayState: Equatable {
    private(set) var pendingRoute: ImportConflictBatchRoute?

    mutating func enqueue(_ route: ImportConflictBatchRoute) {
        pendingRoute = route
    }

    mutating func consumePendingRoute() -> ImportConflictBatchRoute? {
        defer { pendingRoute = nil }
        return pendingRoute
    }
}

private struct ImportConflictBatchRelayModifier: ViewModifier {
    @Binding var relayState: ImportConflictBatchRelayState
    let onOpen: (ImportConflictBatchRoute) -> Void

    func body(content: Content) -> some View {
        content.onChange(of: relayState.pendingRoute) { _, pendingRoute in
            guard pendingRoute != nil,
                  let route = relayState.consumePendingRoute() else { return }
            onOpen(route)
        }
    }
}

extension View {
    func mainRepositoryImportConflictBatchRelay(
        relayState: Binding<ImportConflictBatchRelayState>,
        onOpen: @escaping (ImportConflictBatchRoute) -> Void
    ) -> some View {
        modifier(ImportConflictBatchRelayModifier(relayState: relayState, onOpen: onOpen))
    }
}
