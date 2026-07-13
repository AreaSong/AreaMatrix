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

extension MainRepositoryContentView {
    func applyMainRepositoryImportConflictBatchRelay(to content: some View) -> some View {
        content.onChange(of: importConflictBatchRelayState.pendingRoute) { _, pendingRoute in
            guard pendingRoute != nil,
                  let route = importConflictBatchRelayState.consumePendingRoute() else { return }
            onOpenImportConflictBatch(route)
        }
    }
}
