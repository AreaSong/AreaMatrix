import Foundation

public enum MainListFiltering {
    public static func visibleItems<Item>(
        from items: [Item],
        filterText: String,
        isInSelectedScope: (Item) -> Bool,
        displayName: (Item) -> String
    ) -> [Item] {
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            isInSelectedScope(item) && matches(displayName(item), query: query)
        }
    }

    private static func matches(_ displayName: String, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return displayName.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil
    }
}
