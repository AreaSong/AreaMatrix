import AreaMatrixCoreBridgeContract
import Foundation

/// Non-localized list projection owned by the Library feature group.
///
/// The App target supplies the selected-scope predicate and resolves the final
/// localized count text at the View boundary.
public struct MainListProjection: Equatable, Sendable {
    public let visibleFiles: [FileEntrySnapshot]
    public let resultCount: Int64
    public let isSearchActive: Bool

    public struct SearchContext: Equatable, Sendable {
        public let isActive: Bool
        public let resultCount: Int64?

        public init(isActive: Bool, resultCount: Int64?) {
            self.isActive = isActive
            self.resultCount = resultCount
        }
    }

    public init(visibleFiles: [FileEntrySnapshot], resultCount: Int64, isSearchActive: Bool) {
        self.visibleFiles = visibleFiles
        self.resultCount = resultCount
        self.isSearchActive = isSearchActive
    }

    public static func make(
        files: [FileEntrySnapshot],
        filterText: String,
        isInSelectedScope: @escaping (FileEntrySnapshot) -> Bool,
        sortOrder: [KeyPathComparator<FileEntrySnapshot>],
        search: SearchContext
    ) -> Self {
        let visibleFiles = search.isActive
            ? files
            : MainListFiltering.visibleItems(
                from: files,
                filterText: filterText,
                isInSelectedScope: isInSelectedScope,
                displayName: \FileEntrySnapshot.currentName
            ).sorted(using: sortOrder)
        return Self(
            visibleFiles: visibleFiles,
            resultCount: search.resultCount ?? Int64(visibleFiles.count),
            isSearchActive: search.isActive
        )
    }
}
