public struct MainListLoadingState: Equatable, Sendable {
    public var isLoading: Bool
    public var hasMore: Bool
    public var isLoadingMore: Bool
    public var nextOffset: Int64

    public init(
        isLoading: Bool = false,
        hasMore: Bool = false,
        isLoadingMore: Bool = false,
        nextOffset: Int64 = 0
    ) {
        self.isLoading = isLoading
        self.hasMore = hasMore
        self.isLoadingMore = isLoadingMore
        self.nextOffset = nextOffset
    }

    public mutating func resetPagination() {
        hasMore = false
        isLoadingMore = false
        nextOffset = 0
    }

    public mutating func apply(_ pagination: MainListPagination) {
        nextOffset = pagination.nextOffset
        hasMore = pagination.hasMore
    }
}
