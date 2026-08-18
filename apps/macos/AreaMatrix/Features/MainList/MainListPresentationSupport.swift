import AreaMatrixFeatureLibrary
import AreaMatrixUIFoundation
import Foundation
import SwiftUI

struct MainListPresentationProjection {
    let visibleFiles: [FileEntrySnapshot]
    let listCountText: String

    static func make(
        files: [FileEntrySnapshot],
        sidebarRow: RepositorySidebarRowSnapshot,
        filterText: String,
        sortOrder: [KeyPathComparator<FileEntrySnapshot>],
        search: MainListSearchPresentation
    ) -> Self {
        let projection = MainListProjection.make(
            files: files,
            filterText: filterText,
            isInSelectedScope: sidebarRow.contains,
            sortOrder: sortOrder,
            search: MainListProjection.SearchContext(
                isActive: search.isActive,
                resultCount: search.resultCount
            )
        )
        return Self(
            visibleFiles: projection.visibleFiles,
            listCountText: search.isActive
                ? L10n.plural("mainList.searchResultCount", count: projection.resultCount)
                : L10n.plural("mainList.filesLoaded", count: projection.resultCount)
        )
    }
}

struct MainListSearchPresentation {
    let isActive: Bool
    let resultCount: Int64?
}

extension FileEntrySnapshot {
    var categoryPathDisplay: String {
        FileEntryDisplay.categoryPath(for: self)
    }

    var sizeDisplay: String {
        FileEntryDisplay.size(for: self)
    }

    var importedAtDisplay: String {
        FileEntryDisplay.importedAt(for: self)
    }

    var updatedAtDisplay: String {
        FileEntryDisplay.updatedAt(for: self)
    }
}

struct MainListStatusBannerView: View {
    let banner: MainListStatusBanner
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        TintedStatusBanner(
            tint: .yellow,
            cornerRadius: 0,
            fillsWidth: false,
            contentPadding: 10,
            backgroundOpacity: 0.12
        ) {
            HStack(spacing: 10) {
                Label(banner.message, systemImage: banner.systemImage)
                    .font(.callout)
                Spacer()
                Button(L10n.string("Retry"), action: onRetry)
                Button(L10n.string("Dismiss"), action: onDismiss)
            }
        }
    }
}
