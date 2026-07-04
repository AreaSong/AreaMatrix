@testable import AreaMatrix

extension SavedSearchSnapshot {
    static func mainRepoSavedSearchFixture(
        id: Int64,
        request: CreateSavedSearchRequestSnapshot
    ) -> SavedSearchSnapshot {
        SavedSearchSnapshot(
            id: id,
            name: request.name,
            query: request.query,
            icon: request.icon,
            color: request.color,
            pinned: request.pinned,
            createdAt: 1_700_000_000,
            updatedAt: 1_700_000_000
        )
    }
}
