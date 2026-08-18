import AreaMatrixUIFoundation
import SwiftUI

struct SearchIndexingStatusRouteView: View {
    let request: SearchQueryRequestSnapshot
    let indexStatus: SearchIndexStatusSnapshot?
    let onRetry: () -> Void
    let onClose: () -> Void

    var body: some View {
        AreaMatrixActionSheetContainer(
            title: L10n.string("Search Index Status"),
            pageID: "search-index-status-indexing-status"
        ) {
            Label(statusText, systemImage: "exclamationmark.triangle")
                .font(.callout)
            metadataRow("Query", request.query)
            metadataRow("Scope", request.scope.displayName)
            HStack {
                Spacer()
                Button(L10n.string("Close"), action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button(L10n.string("Retry"), action: onRetry)
            }
        }
        .accessibilityIdentifier("search-index-status-indexing-status-search-route")
    }

    private var statusText: String {
        switch indexStatus {
        case .unavailable:
            L10n.string("Search index unavailable")
        case .indexing:
            L10n.string("Search index is updating")
        case .ready:
            L10n.string("Search index ready")
        case nil:
            L10n.string("Search index status unavailable")
        }
    }
}

func searchContextText(_ request: SearchQueryRequestSnapshot) -> String {
    L10n.format("search.context", request.scope.displayName, request.sort.displayName)
}
