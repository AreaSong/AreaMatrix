import SwiftUI

@MainActor
final class ConnectRepositoryRouteCoordinator: ObservableObject {
    @Published private(set) var activeRoute: MobileRepositoryConnectionRoute?
    @Published var isPresented = false

    func update(_ route: MobileRepositoryConnectionRoute?) {
        activeRoute = route
        isPresented = route != nil
    }

    func dismiss() {
        activeRoute = nil
        isPresented = false
    }
}

struct ConnectRepositoryRouteDestinationContent: Equatable {
    var title: String
    var systemImage: String
    var primaryText: String
    var pathText: String?

    init(route: MobileRepositoryConnectionRoute) {
        switch route {
        case let .mobileLibrary(connection):
            title = "Mobile Library"
            systemImage = "folder"
            primaryText = "Repository connected."
            pathText = connection.validation.repoPath
        case let .repositoryInitConfirm(candidate):
            title = "Initialize Repository"
            systemImage = "checkmark.shield"
            primaryText = "Review this empty folder before AreaMatrix creates metadata."
            pathText = candidate.validation.repoPath
        case let .repositoryAdoptConfirm(candidate):
            title = "Adopt Repository"
            systemImage = "folder.badge.plus"
            primaryText = "Review this folder before AreaMatrix adopts it."
            pathText = candidate.validation.repoPath
        case let .iCloudPermission(error):
            title = "iCloud Permission"
            systemImage = "icloud.slash"
            primaryText = error.message
            pathText = nil
        }
    }
}

struct ConnectRepositoryRouteDestinationView: View {
    private let route: MobileRepositoryConnectionRoute
    private let mobileLibraryBridge: any MobileLibraryCoreBridge
    private let missingFileRecoveryBridge: any MissingFileRecoveryCoreBridge
    private let cloudState: MobileCloudStorageState?
    private let isChecking: Bool
    private let isCreatingRepository: Bool
    private let repositoryError: MobileRepositoryConnectionError?
    private let onRefreshRepositoryInit: (MobileRepositoryCandidate) -> Void
    private let onCreateRepository: (MobileRepositoryCandidate) -> Void
    private let onRefreshRepositoryAdopt: (MobileRepositoryCandidate) -> Void
    private let onAdoptRepository: (MobileRepositoryCandidate) -> Void
    private let onTryAgain: () -> Void
    private let onReconnectFolder: () -> Void
    private let onChooseAnotherFolder: () -> Void
    private let onCancelRepositoryInit: () -> Void
    private let onOpenSettings: () -> Void
    private let onOpenSyncConflictReview: (SyncConflictEntryReviewRoute) -> Void
    @State private var pendingMissingFileRecoveryRoute: MissingFileRecoveryRoute?

    init(
        route: MobileRepositoryConnectionRoute,
        mobileLibraryBridge: any MobileLibraryCoreBridge = LiveMobileRepositoryCoreBridge(),
        missingFileRecoveryBridge: any MissingFileRecoveryCoreBridge = LiveMobileRepositoryCoreBridge(),
        cloudState: MobileCloudStorageState? = nil,
        isChecking: Bool = false,
        isCreatingRepository: Bool = false,
        repositoryError: MobileRepositoryConnectionError? = nil,
        onRefreshRepositoryInit: @escaping (MobileRepositoryCandidate) -> Void = { _ in },
        onCreateRepository: @escaping (MobileRepositoryCandidate) -> Void = { _ in },
        onRefreshRepositoryAdopt: @escaping (MobileRepositoryCandidate) -> Void = { _ in },
        onAdoptRepository: @escaping (MobileRepositoryCandidate) -> Void = { _ in },
        onTryAgain: @escaping () -> Void = {},
        onReconnectFolder: @escaping () -> Void = {},
        onChooseAnotherFolder: @escaping () -> Void = {},
        onCancelRepositoryInit: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {},
        onOpenSyncConflictReview: @escaping (SyncConflictEntryReviewRoute) -> Void = { _ in }
    ) {
        self.route = route
        self.mobileLibraryBridge = mobileLibraryBridge
        self.missingFileRecoveryBridge = missingFileRecoveryBridge
        self.cloudState = cloudState
        self.isChecking = isChecking
        self.isCreatingRepository = isCreatingRepository
        self.repositoryError = repositoryError
        self.onRefreshRepositoryInit = onRefreshRepositoryInit
        self.onCreateRepository = onCreateRepository
        self.onRefreshRepositoryAdopt = onRefreshRepositoryAdopt
        self.onAdoptRepository = onAdoptRepository
        self.onTryAgain = onTryAgain
        self.onReconnectFolder = onReconnectFolder
        self.onChooseAnotherFolder = onChooseAnotherFolder
        self.onCancelRepositoryInit = onCancelRepositoryInit
        self.onOpenSettings = onOpenSettings
        self.onOpenSyncConflictReview = onOpenSyncConflictReview
    }

    var body: some View {
        switch route {
        case let .mobileLibrary(connection):
            MobileLibraryView(
                connection: connection,
                bridge: mobileLibraryBridge,
                onOpenMissingRecovery: { fileID in
                    openMissingFileRecovery(repoPath: connection.validation.repoPath, fileID: fileID)
                },
                onOpenSyncConflictReview: onOpenSyncConflictReview
            )
            .sheet(item: $pendingMissingFileRecoveryRoute) { route in
                MissingFileRecoveryView(
                    model: MissingFileRecoveryViewModel(
                        repoPath: route.repoPath,
                        fileID: route.fileID,
                        bridge: missingFileRecoveryBridge
                    ),
                    onDecideLater: dismissMissingFileRecovery
                )
            }
        case let .repositoryInitConfirm(candidate):
            RepositoryInitConfirmView(
                candidate: candidate,
                isChecking: isChecking,
                isCreating: isCreatingRepository,
                error: repositoryError,
                onRefresh: onRefreshRepositoryInit,
                onCreate: onCreateRepository,
                onChooseAnotherFolder: onChooseAnotherFolder,
                onCancel: onCancelRepositoryInit
            )
        case let .repositoryAdoptConfirm(candidate):
            RepositoryAdoptConfirmView(
                candidate: candidate,
                isChecking: isChecking,
                isCreating: isCreatingRepository,
                error: repositoryError,
                onRefresh: onRefreshRepositoryAdopt,
                onAdopt: onAdoptRepository,
                onChooseAnotherFolder: onChooseAnotherFolder,
                onCancel: onCancelRepositoryInit
            )
        case let .iCloudPermission(error):
            ICloudPermissionView(
                content: ICloudPermissionContent(error: error, cloudState: cloudState),
                isChecking: isChecking,
                onTryAgain: onTryAgain,
                onReconnectFolder: onReconnectFolder,
                onChooseAnotherFolder: onChooseAnotherFolder,
                onOpenSettings: onOpenSettings
            )
        }
    }

    private func openMissingFileRecovery(repoPath: String, fileID: Int64) {
        pendingMissingFileRecoveryRoute = MissingFileRecoveryRoute(repoPath: repoPath, fileID: fileID)
    }

    private func dismissMissingFileRecovery() {
        pendingMissingFileRecoveryRoute = nil
    }
}

struct ConnectRepositoryHelpContent: Equatable {
    var title: String
    var rows: [String]

    static let repositoryHelp = ConnectRepositoryHelpContent(
        title: "Repository Help",
        rows: [
            "A repository is a normal folder that contains AreaMatrix metadata.",
            "AreaMatrix only reads the folder structure before you confirm initialization or adoption.",
            "iCloud Drive lets this iOS app share the same repository folder with your Mac."
        ]
    )
}

struct ConnectRepositoryHelpView: View {
    @Environment(\.dismiss) private var dismiss
    private let content = ConnectRepositoryHelpContent.repositoryHelp

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        PlatformDifferencesView()
                    } label: {
                        Label("Platform capabilities", systemImage: "list.bullet.rectangle")
                    }
                    .accessibilityLabel("Platform capabilities")
                }

                Section {
                    ForEach(content.rows, id: \.self) { row in
                        Text(row)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .connectRepositoryListStyle()
            .navigationTitle(content.title)
            .toolbar {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}
