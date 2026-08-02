import SwiftUI

#if DEBUG
@MainActor
struct DeveloperSyncConflictScenarioView: View {
    let scenario: AreaMatrixDeveloperScenario

    var body: some View {
        switch scenario {
        case .syncConflictsICloudList:
            iCloudList
        case .syncConflictsICloudMinimal:
            iCloudMinimal
        case .syncConflictsEntry:
            syncEntry
        case .syncConflictsReplaceConfirmation:
            syncReplaceConfirmation
        case .syncConflictsReview:
            syncReview
        default:
            EmptyView()
        }
    }

    private var iCloudList: some View {
        let core = DeveloperSyncConflictCoreFixture()
        let platform = DeveloperSyncConflictPlatformActions()
        let model = ICloudConflictListModel(
            repoPath: fixture.repoPath,
            conflictLister: core,
            errorMapper: CoreErrorSnapshotMapper(),
            repositoryFinderOpener: platform,
            fileRevealer: platform
        )
        return ICloudConflictListView(
            model: model,
            systemCapabilityChecker: DeveloperMainListSystemCapabilityChecker(),
            onClose: {},
            onResolve: { _ in },
            makeResolutionModel: { route in
                ICloudConflictMinimalModel(
                    repoPath: route.repoPath,
                    conflictID: route.conflict.conflictID,
                    originalVersion: route.originalVersion,
                    conflictedCopyVersion: route.conflictedCopyVersion,
                    pathValidator: core,
                    conflictReviewer: core,
                    errorMapper: CoreErrorSnapshotMapper()
                )
            }
        )
        .background(.background)
    }

    private var iCloudMinimal: some View {
        let core = DeveloperSyncConflictCoreFixture()
        let route = ICloudConflictMinimalRouteContext(repoPath: fixture.repoPath, conflict: fixture.iCloudPair)
        return ICloudConflictMinimalSheet(
            model: ICloudConflictMinimalModel(
                repoPath: route.repoPath,
                conflictID: route.conflict.conflictID,
                originalVersion: route.originalVersion,
                conflictedCopyVersion: route.conflictedCopyVersion,
                pathValidator: core,
                conflictReviewer: core,
                errorMapper: CoreErrorSnapshotMapper()
            ),
            resolutionCapability: .supported,
            isTrashAvailable: false,
            onCancel: {},
            onApply: { _ in }
        )
        .background(.background)
    }

    private var syncEntry: some View {
        SyncConflictEntryPanel(
            model: SyncConflictEntryModel(
                repoPath: fixture.repoPath,
                conflictDetector: DeveloperSyncConflictCoreFixture(),
                errorMapper: CoreErrorSnapshotMapper()
            ),
            onReview: { _ in }
        )
        .padding(24)
        .frame(maxWidth: 760, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
    }

    private var syncReplaceConfirmation: some View {
        SyncConflictReplaceConfirmationPanel(
            preview: fixture.replacePreview,
            confirmation: nil,
            disabledReason: nil,
            onConfirm: { _ in }
        )
        .padding(24)
        .frame(maxWidth: 760, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
    }

    private var syncReview: some View {
        let core = DeveloperSyncConflictCoreFixture()
        return SyncConflictReviewView(
            model: SyncConflictReviewModel(
                repoPath: fixture.repoPath,
                conflictID: fixture.syncConflict.conflictID,
                conflictDetector: core,
                conflictResolver: core,
                errorMapper: CoreErrorSnapshotMapper()
            ),
            onBackToNeedsReview: {},
            onClose: {}
        )
        .background(.background)
    }
}

private let fixture = DeveloperSyncConflictScenarioFixture.self
#endif
