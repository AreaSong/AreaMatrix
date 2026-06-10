import SwiftUI

public struct ConnectRepositoryEntryView: View {
    @StateObject private var model = ConnectRepositoryModel(bridge: LiveMobileRepositoryCoreBridge())
    @State private var pendingMissingFileRecoveryRoute: MissingFileRecoveryRoute?
    @State private var pendingSyncConflictReviewRoute: SyncConflictEntryReviewRoute?

    public init() {}

    public var body: some View {
        Group {
            if let connection = model.shareImportTakeoverConnection {
                NavigationStack {
                    MobileLibraryView(
                        connection: connection,
                        bridge: LiveMobileRepositoryCoreBridge(),
                        onOpenMissingRecovery: { fileID in
                            openMissingFileRecovery(repoPath: connection.validation.repoPath, fileID: fileID)
                        },
                        onOpenSyncConflictReview: openSyncConflictReview
                    )
                    .toolbar {
                        NavigationLink {
                            PlatformDifferencesView(repositoryPath: connection.validation.repoPath)
                        } label: {
                            Image(systemName: "list.bullet.rectangle")
                        }
                        .accessibilityLabel("Platform capabilities")
                    }
                    .sheet(item: $pendingMissingFileRecoveryRoute) { route in
                        MissingFileRecoveryView(
                            model: MissingFileRecoveryViewModel(
                                repoPath: route.repoPath,
                                fileID: route.fileID,
                                bridge: LiveMobileRepositoryCoreBridge()
                            ),
                            onDecideLater: dismissMissingFileRecovery
                        )
                    }
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

    private func openMissingFileRecovery(repoPath: String, fileID: Int64) {
        pendingMissingFileRecoveryRoute = MissingFileRecoveryRoute(repoPath: repoPath, fileID: fileID)
    }

    private func dismissMissingFileRecovery() {
        pendingMissingFileRecoveryRoute = nil
    }

    private func openSyncConflictReview(_ route: SyncConflictEntryReviewRoute) {
        pendingSyncConflictReviewRoute = route
    }
}
