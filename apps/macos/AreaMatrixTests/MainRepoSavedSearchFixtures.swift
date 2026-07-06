@testable import AreaMatrix

extension SavedSearchSnapshot {
    static func mainRepoSavedSearchFixture(
        id: Int64,
        request: CreateSavedSearchRequestSnapshot
    ) -> SavedSearchSnapshot {
        .testFixture(id: id, request: request)
    }
}
