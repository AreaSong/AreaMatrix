import AreaMatrixUIFoundation
import SwiftUI

extension MainRepositoryContentView {
    @ViewBuilder
    var listPane: some View {
        if let error = currentListError {
            MainCurrentListErrorPane(
                error: error,
                state: state,
                fileListModel: fileListModel,
                recoveryActions: mainListErrorRecoveryActions
            )
        } else {
            listContentPane
        }
    }

    private var selectedListTitle: String {
        selectedSidebarRow.displayName
    }

    private var currentListError: CoreErrorMappingSnapshot? {
        state == .list ? fileListModel.errorMapping : opening.currentCategoryListError
    }

    @ViewBuilder
    private var listContentPane: some View {
        switch state {
        case .empty:
            AreaMatrixEmptyStateView(
                systemImage: "tray.and.arrow.down",
                title: L10n.string("main.empty.title"),
                message: L10n.string("main.empty.message"),
                primaryTitle: opening.isReadOnly ? nil : L10n.string("Import..."),
                primaryAction: opening.isReadOnly ? nil : onImport
            )
            .modifier(ImportDropTargetModifier(
                target: .autoClassify,
                dropPreviewModel: dropPreviewModel,
                onDropImport: { urls, target in
                    onDropImport(urls, target.entryDestination)
                },
                isEnabled: !opening.isReadOnly
            ))
            .accessibilityElement(children: .contain)
        case .list:
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(selectedListTitle)
                        .font(.title3.weight(.semibold))
                    Text(mainListPresentation.listCountText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    listLoadingIndicator
                }
                Divider()
                mainListStatusRegion
                fileTable
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .areaMatrixWorkspaceRegionShell(cornerRadius: 14)
            .padding(10)
            .modifier(ImportDropTargetModifier(
                target: selectedSidebarRow.importDropTarget,
                dropPreviewModel: dropPreviewModel,
                onDropImport: { urls, target in
                    onDropImport(urls, target.entryDestination)
                },
                isEnabled: !opening.isReadOnly
            ))
        }
    }

    @ViewBuilder
    private var mainListStatusRegion: some View {
        if searchModel.searchState.isActive {
            searchStatusBanner
        } else if let banner = fileListModel.statusBanner {
            MainListStatusBannerView(
                banner: banner,
                onRetry: { Task { await fileListModel.retryCurrentCategory() } },
                onDismiss: fileListModel.clearStatusBanner
            )
        } else if state == .list {
            SyncConflictEntryPanel(model: syncConflictEntryModel) { route in
                syncConflictCoordinator.reviewRoutingState.route = route
            }
        }
    }

    @ViewBuilder
    private var listLoadingIndicator: some View {
        if let loadingStatus = fileListModel.loadingStatusText {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(loadingStatus)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(fileListModel.loadingAccessibilityText ?? L10n.string("Loading files"))
        }
    }
}
