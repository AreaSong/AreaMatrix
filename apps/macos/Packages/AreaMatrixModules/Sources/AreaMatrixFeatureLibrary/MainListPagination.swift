public struct MainListPagination: Equatable, Sendable {
    public static let defaultPageSize: Int64 = 50

    public private(set) var nextOffset: Int64
    public private(set) var hasMore: Bool

    public init(initialCount: Int, pageSize: Int64 = Self.defaultPageSize) {
        nextOffset = Int64(initialCount)
        hasMore = initialCount == Int(pageSize)
    }

    public mutating func reset() {
        nextOffset = 0
        hasMore = false
    }

    public mutating func replace(itemCount: Int, requestedLimit: Int64) {
        nextOffset = Int64(itemCount)
        hasMore = itemCount == Int(requestedLimit)
    }

    public mutating func append(itemCount: Int, pageSize: Int64 = Self.defaultPageSize) {
        nextOffset += Int64(itemCount)
        hasMore = itemCount == Int(pageSize)
    }

    public func reloadLimit(pageSize: Int64 = Self.defaultPageSize) -> Int64 {
        max(pageSize, nextOffset)
    }

    public static func mergingUnique<Item, ID: Hashable>(
        existing: [Item],
        appending loaded: [Item],
        id: (Item) -> ID
    ) -> [Item] {
        var merged: [Item] = []
        var indexByID: [ID: Int] = [:]
        for item in existing + loaded {
            let itemID = id(item)
            if let index = indexByID[itemID] {
                merged[index] = item
            } else {
                indexByID[itemID] = merged.count
                merged.append(item)
            }
        }
        return merged
    }
}
