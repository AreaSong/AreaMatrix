import Foundation

enum DetailTagEditorOperation: Equatable {
    case load
    case add(String)
    case remove(String)

    var tag: String? {
        switch self {
        case .load:
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

extension CoreErrorMappingSnapshot {
    static func batchTagFileSelectionMissing() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .fileNotFound,
            userMessage: "No files selected",
            severity: .medium,
            suggestedAction: "Select files before adding tags.",
            recoverability: .userActionRequired,
            rawContext: "S2-09 C2-06 batch_add_tags"
        )
    }
}

enum TagInputNormalization {
    static let invalidMessage = "Tag name is invalid."
    private static let maxTagLength = 64
    private static let reservedValues: Set<String> = [".", "..", ".areamatrix", "areamatrix"]

    static func normalizedValue(_ rawValue: String) -> String? {
        validationMessage(for: rawValue) == nil ? rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() : nil
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

struct BatchTagPendingState: Equatable {
    var input: String
    var pendingTags: [String]
    var fieldError: String?
}

struct BatchAddTagsApplyResult: Equatable {
    var report: BatchMutationReportSnapshot?
    var failure: CoreErrorMappingSnapshot?
}

enum BatchPendingTagStatus: String, Equatable {
    case ready = "Ready"
    case alreadySelected = "Already selected"
    case invalid = "Invalid"
    case blocked = "Blocked"

    var preventsApply: Bool {
        self != .ready
    }
}

struct BatchPendingTagChip: Equatable {
    var value: String
    var status: BatchPendingTagStatus
    var message: String?
}

enum BatchTagApplyNormalizationResult: Equatable {
    case success([String])
    case failure(String)
}

enum BatchTagCatalogState: Equatable {
    case idle
    case loading(previous: TagSetSnapshot?)
    case loaded(TagSetSnapshot)
    case failed(CoreErrorMappingSnapshot, previous: TagSetSnapshot?)

    var tagSet: TagSetSnapshot? {
        switch self {
        case let .loaded(tagSet), let .loading(tagSet?), let .failed(_, tagSet?):
            tagSet
        case .idle, .loading, .failed:
            nil
        }
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var failure: CoreErrorMappingSnapshot? {
        guard case let .failed(mapping, _) = self else { return nil }
        return mapping
    }
}

enum BatchTagCatalogAction {
    static func load(
        repoPath: String,
        fileIDs: [Int64],
        tagStore: any CoreTagCRUD,
        errorMapper: any CoreErrorMapping
    ) async -> BatchTagCatalogState {
        guard let anchorFileID = fileIDs.first else {
            return .failed(.batchTagFileSelectionMissing(), previous: nil)
        }
        do {
            return .loaded(try await tagStore.listTags(repoPath: repoPath, fileID: anchorFileID))
        } catch {
            return .failed(await mapError(error, errorMapper: errorMapper), previous: nil)
        }
    }

    private static func mapError(_ error: Error, errorMapper: any CoreErrorMapping) async -> CoreErrorMappingSnapshot {
        if let coreError = error as? CoreError { return await errorMapper.mapCoreError(coreError) }
        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
    }
}

enum BatchTagValidation {
    static func normalized(_ rawValue: String) -> String {
        TagInputNormalization.normalizedValue(rawValue) ?? rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func message(for rawValue: String) -> String? {
        TagInputNormalization.validationMessage(for: rawValue)
    }

    static func pendingStateAfterAdding(
        input: String,
        pendingTags: [String],
        catalog: TagSetSnapshot? = nil,
        disabledReason: String?
    ) -> BatchTagPendingState {
        if disabledReason != nil {
            return BatchTagPendingState(input: input, pendingTags: pendingTags, fieldError: "Tag store is read-only.")
        }
        guard let normalizedValue = TagInputNormalization.normalizedValue(input) else {
            return BatchTagPendingState(input: input, pendingTags: pendingTags, fieldError: TagInputNormalization.invalidMessage)
        }
        let value = matchingKnownTagValue(normalizedValue, catalog: catalog) ?? normalizedValue
        if pendingTags.contains(where: { normalized($0) == value }) {
            return BatchTagPendingState(input: input, pendingTags: pendingTags, fieldError: "Tag already selected.")
        }
        if catalog?.allKnownTags.first(where: { $0.value == value })?.disabled == true {
            return BatchTagPendingState(input: input, pendingTags: pendingTags, fieldError: "Tag store is read-only.")
        }
        return BatchTagPendingState(input: "", pendingTags: pendingTags + [value], fieldError: nil)
    }

    static func pendingChips(pendingTags: [String], disabledReason: String?) -> [BatchPendingTagChip] {
        var seenTags: Set<String> = []
        return pendingTags.map { tag in
            guard disabledReason == nil else {
                return BatchPendingTagChip(value: tag, status: .blocked, message: "Tag store is read-only.")
            }
            guard let normalized = TagInputNormalization.normalizedValue(tag) else {
                return BatchPendingTagChip(value: tag, status: .invalid, message: TagInputNormalization.invalidMessage)
            }
            if seenTags.contains(normalized) {
                return BatchPendingTagChip(value: tag, status: .alreadySelected, message: "Tag already selected.")
            }
            seenTags.insert(normalized)
            return BatchPendingTagChip(value: normalized, status: .ready, message: nil)
        }
    }

    static func visibleCandidates(input: String, catalog: TagSetSnapshot?, pendingTags: [String]) -> [TagRecordSnapshot] {
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let source = query.isEmpty ? catalog?.recentTags ?? [] : catalog?.availableTags ?? []
        let filtered = query.isEmpty ? source : source.filter {
            $0.value.localizedCaseInsensitiveContains(query) || $0.displayName.localizedCaseInsensitiveContains(query)
        }
        return filtered.map { tag in
            var updated = tag
            updated.selected = pendingTags.contains { normalized($0) == tag.value }
            return updated
        }
    }

    static func canApply(
        isApplying: Bool,
        disabledReason: String?,
        input: String,
        pendingTags: [String],
        fieldError: String?,
        selectedCount: Int
    ) -> Bool {
        guard !isApplying, selectedCount > 0, disabledReason == nil, !pendingTags.isEmpty, fieldError == nil else {
            return false
        }
        guard input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return pendingChips(pendingTags: pendingTags, disabledReason: disabledReason).allSatisfy { !$0.status.preventsApply }
    }

    static func normalizedTagsForApply(_ pendingTags: [String]) -> BatchTagApplyNormalizationResult {
        let chips = pendingChips(pendingTags: pendingTags, disabledReason: nil)
        guard chips.allSatisfy({ !$0.status.preventsApply }) else {
            return .failure(chips.first { $0.status.preventsApply }?.message ?? TagInputNormalization.invalidMessage)
        }
        return .success(chips.map(\.value))
    }

    private static func matchingKnownTagValue(_ normalized: String, catalog: TagSetSnapshot?) -> String? {
        catalog?.allKnownTags.first { $0.value.caseInsensitiveCompare(normalized) == .orderedSame }?.value
    }
}

enum BatchAddTagsAction {
    static func apply(
        repoPath: String,
        fileIDs: [Int64],
        tags: [String],
        tagStore: any CoreTagCRUD,
        errorMapper: any CoreErrorMapping
    ) async -> BatchAddTagsApplyResult {
        do {
            let report = try await tagStore.batchAddTags(repoPath: repoPath, fileIDs: fileIDs, tags: tags)
            return BatchAddTagsApplyResult(report: report, failure: nil)
        } catch {
            return BatchAddTagsApplyResult(report: nil, failure: await mapError(error, errorMapper: errorMapper))
        }
    }

    private static func mapError(_ error: Error, errorMapper: any CoreErrorMapping) async -> CoreErrorMappingSnapshot {
        if let coreError = error as? CoreError { return await errorMapper.mapCoreError(coreError) }
        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
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
