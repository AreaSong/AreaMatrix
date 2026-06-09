import SwiftUI

public struct ConnectRepositoryEntryView: View {
    @StateObject private var model = ConnectRepositoryModel(bridge: LiveMobileRepositoryCoreBridge())
    @State private var pendingSyncConflictReviewRoute: SyncConflictEntryReviewRoute?

    public init() {}

    public var body: some View {
        Group {
            if let connection = model.shareImportTakeoverConnection {
                NavigationStack {
                    MobileLibraryView(
                        connection: connection,
                        bridge: LiveMobileRepositoryCoreBridge(),
                        onOpenSyncConflictReview: openSyncConflictReview
                    )
                    .navigationDestination(item: $pendingSyncConflictReviewRoute) { route in
                        SyncConflictReviewRouteView(route: route)
                    }
                }
            } else {
                ConnectRepositoryView(model: model)
            }
        }
        .onOpenURL { url in
            Task { await model.handleOpenURL(url) }
        }
    }

    private func openSyncConflictReview(_ route: SyncConflictEntryReviewRoute) {
        pendingSyncConflictReviewRoute = route
    }
}
