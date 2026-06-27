import Foundation

enum DetailTagEditorOperation: Equatable {
    case load
    case add(String)
    case remove(String)
    case suggest
    case applySuggestions([String])

    var tag: String? {
        switch self {
        case .load, .suggest, .applySuggestions:
            nil
        case let .add(tag), let .remove(tag):
            tag
        }
    }
}

enum DetailTagUndoAction: String, Equatable {
    case removeAddedTag
    case restoreRemovedTag
}

struct DetailTagUndoToast: Equatable, Identifiable {
    let fileID: Int64
    let tagValue: String
    let tagLabel: String
    let action: DetailTagUndoAction

    var id: String {
        "\(fileID):\(action.rawValue):\(tagValue)"
    }

    var message: String {
        switch action {
        case .removeAddedTag:
            "Added tag \"\(displayName)\"."
        case .restoreRemovedTag:
            "Removed tag \"\(displayName)\"."
        }
    }

    var undoOperation: DetailTagEditorOperation {
        switch action {
        case .removeAddedTag:
            .remove(tagValue)
        case .restoreRemovedTag:
            .add(tagValue)
        }
    }

    func belongs(to fileID: Int64) -> Bool {
        self.fileID == fileID
    }

    private var displayName: String {
        tagLabel.isEmpty ? tagValue : tagLabel
    }
}

extension DetailTagUndoToast {
    static func addedTag(
        fileID: Int64,
        previous: TagSetSnapshot?,
        current: TagSetSnapshot
    ) -> DetailTagUndoToast? {
        guard let tag = current.fileTags.first(where: { tag in
            previous?.containsFileTag(value: tag.value) != true
        }) else { return nil }

        return DetailTagUndoToast(
            fileID: fileID,
            tagValue: tag.value,
            tagLabel: tag.displayName,
            action: .removeAddedTag
        )
    }

    static func removedTag(
        fileID: Int64,
        previous: TagSetSnapshot?,
        current: TagSetSnapshot
    ) -> DetailTagUndoToast? {
        guard let tag = previous?.fileTags.first(where: { tag in
            !current.containsFileTag(value: tag.value)
        }) else { return nil }

        return DetailTagUndoToast(
            fileID: fileID,
            tagValue: tag.value,
            tagLabel: tag.displayName,
            action: .restoreRemovedTag
        )
    }
}

enum DetailTagEditorState: Equatable {
    case notLoaded
    case loading(fileID: Int64, previous: TagSetSnapshot?)
    case loaded(fileID: Int64, TagSetSnapshot)
    case failed(fileID: Int64, operation: DetailTagEditorOperation, CoreErrorMappingSnapshot, previous: TagSetSnapshot?)

    var tagSet: TagSetSnapshot? {
        switch self {
        case let .loaded(_, tagSet), let .loading(_, tagSet?),
             let .failed(_, _, _, tagSet?):
            tagSet
        case .notLoaded, .loading, .failed:
            nil
        }
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var failure: (operation: DetailTagEditorOperation, mapping: CoreErrorMappingSnapshot)? {
        guard case let .failed(_, operation, mapping, _) = self else { return nil }
        return (operation, mapping)
    }
}

extension TagSetSnapshot {
    func containsFileTag(value: String) -> Bool {
        fileTags.contains { $0.value.caseInsensitiveCompare(value) == .orderedSame }
    }

    var allKnownTags: [TagRecordSnapshot] {
        var tags = fileTags
        for tag in availableTags + recentTags where !tags.contains(where: { $0.value == tag.value }) {
            tags.append(tag)
        }
        return tags
    }
}

enum TagInputNormalization {
    static let invalidMessage = "Tag name is invalid."
    private static let maxTagLength = 64
    private static let reservedValues: Set<String> = [".", "..", ".areamatrix", "areamatrix"]

    static func normalizedValue(_ rawValue: String) -> String? {
        guard validationMessage(for: rawValue) == nil else { return nil }
        return rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func validationMessage(for rawValue: String) -> String? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty || value.count > maxTagLength { return invalidMessage }
        if value.contains("/") || value.contains("\\") || value.contains(":") || value.contains("\0") {
            return invalidMessage
        }
        if reservedValues.contains(value.lowercased()) { return invalidMessage }
        return nil
    }
}

enum TagFilterRegistryState: Equatable {
    case idle
    case loading(fileID: Int64, previous: TagSetSnapshot?)
    case loaded(fileID: Int64, TagSetSnapshot)
    case failed(fileID: Int64, CoreErrorMappingSnapshot, previous: TagSetSnapshot?)

    var tagSet: TagSetSnapshot? {
        switch self {
        case let .loaded(_, tagSet), let .loading(_, tagSet?),
             let .failed(_, _, tagSet?):
            tagSet
        case .idle, .loading, .failed:
            nil
        }
    }

    var errorMapping: CoreErrorMappingSnapshot? {
        guard case let .failed(_, mapping, _) = self else { return nil }
        return mapping
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

enum TagFacetFiltering {
    static func visibleTags(query: String, facets: [SearchFacetCountSnapshot]) -> [SearchFacetCountSnapshot] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return facets }
        return facets.filter { facet in
            facet.value.localizedCaseInsensitiveContains(normalizedQuery) ||
                facet.label.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }
}

enum TagFilterRegistryPresentation {
    static func options(
        registryState: TagFilterRegistryState,
        facetsState: MainSearchFacetsState
    ) -> [SearchFacetCountSnapshot] {
        let facets = facetsState.facets?.tags ?? []
        guard let tagSet = registryState.tagSet else { return facets }

        var merged = facets
        for tag in tagSet.availableTags where !contains(tag.value, in: merged) {
            merged.append(SearchFacetCountSnapshot(
                value: tag.value,
                label: tag.displayName,
                count: -1,
                selected: tag.selected,
                disabled: tag.disabled
            ))
        }
        return merged
    }

    private static func contains(_ value: String, in facets: [SearchFacetCountSnapshot]) -> Bool {
        facets.contains { $0.value.caseInsensitiveCompare(value) == .orderedSame }
    }
}

extension SearchFacetCountSnapshot {
    var countDisplayText: String {
        if count < 0 || disabled { return "--" }
        return "\(count) files"
    }

    func isSelected(in filters: SearchFilterStateSnapshot) -> Bool {
        filters.tags.contains { $0.caseInsensitiveCompare(value) == .orderedSame }
    }

    func accessibilityLabel(isSelected: Bool) -> String {
        let state = isSelected ? "selected" : "not selected"
        let availability = disabled ? "disabled" : countDisplayText
        return "\(label), \(availability), \(state)"
    }
}

extension SearchTagMatchModeSnapshot {
    var accessibilityText: String {
        switch self {
        case .any:
            "Any selected tag"
        case .all:
            "All selected tags"
        }
    }
}
