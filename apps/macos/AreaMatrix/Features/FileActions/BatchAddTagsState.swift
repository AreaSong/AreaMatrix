import Foundation

struct BatchAddTagsRoute: Identifiable, Equatable {
    let source: MainFileBatchActionRouteSource
    private let payload: MainFileBatchActionRoutePayload

    var fileIDs: [Int64] {
        payload.fileIDs
    }

    var selectedFiles: [FileEntrySnapshot] {
        payload.selectedFiles
    }

    var selectedCount: Int {
        payload.selectedCount
    }

    var disabledReason: String? {
        payload.disabledReason
    }

    var id: String {
        ([source.rawValue] + payload.identityParts).joined(separator: ":")
    }

    init(
        source: MainFileBatchActionRouteSource,
        fileIDs: [Int64],
        selectedFiles: [FileEntrySnapshot] = [],
        selectedCount: Int,
        disabledReason: String?
    ) {
        self.source = source
        payload = MainFileBatchActionRoutePayload(
            fileIDs: fileIDs,
            selectedFiles: selectedFiles,
            selectedCount: selectedCount,
            disabledReason: disabledReason
        )
    }
}

extension BatchAddTagsRoute {
    init(source: MainFileBatchActionRouteSource, context: MainFileBatchActionRouteContext) {
        self.init(source: source, payload: MainFileBatchActionRoutePayload(context: context))
    }

    private init(source: MainFileBatchActionRouteSource, payload: MainFileBatchActionRoutePayload) {
        self.source = source
        self.payload = payload
    }
}

extension CoreErrorMappingSnapshot {
    static func batchTagFileSelectionMissing() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .fileNotFound,
            userMessage: L10n.string("No files selected"),
            severity: .medium,
            suggestedAction: L10n.string("Select files before adding tags."),
            recoverability: .userActionRequired,
            rawContext: "batch-add-tags batch-add-tags-core batch_add_tags"
        )
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

struct BatchTagApplyEligibility: Equatable {
    var isApplying: Bool
    var disabledReason: String?
    var input: String
    var pendingTags: [String]
    var fieldError: String?
    var selectedCount: Int
}

enum BatchPendingTagStatus: String, Equatable {
    case ready = "Ready"
    case alreadySelected = "Already selected"
    case invalid = "Invalid"
    case blocked = "Blocked"

    var preventsApply: Bool {
        self != .ready
    }

    var displayName: String {
        switch self {
        case .ready: L10n.string("Ready")
        case .alreadySelected: L10n.string("Already selected")
        case .invalid: L10n.string("Invalid")
        case .blocked: L10n.string("Blocked")
        }
    }
}

enum BatchAddTagsEntryPolicy {
    static func openHelp(disabledReason: String?) -> String {
        MainFileBatchEntryPolicy.openHelp(
            disabledReason: disabledReason,
            defaultHelp: L10n.string("Add tags to the selected files"),
            blockedHelpSuffix: L10n.string("You can still review selected files and tag candidates.")
        )
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
            return try await .loaded(tagStore.listTags(repoPath: repoPath, fileID: anchorFileID))
        } catch {
            return await .failed(errorMapper.mapError(error), previous: nil)
        }
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
            return BatchTagPendingState(
                input: input,
                pendingTags: pendingTags,
                fieldError: L10n.string("Tag store is read-only.")
            )
        }
        guard let normalizedValue = TagInputNormalization.normalizedValue(input) else {
            return BatchTagPendingState(
                input: input,
                pendingTags: pendingTags,
                fieldError: TagInputNormalization.invalidMessage
            )
        }
        let value = matchingKnownTagValue(normalizedValue, catalog: catalog) ?? normalizedValue
        if pendingTags.contains(where: { normalized($0) == value }) {
            return BatchTagPendingState(
                input: input,
                pendingTags: pendingTags,
                fieldError: L10n.string("Tag already selected.")
            )
        }
        if catalog?.allKnownTags.first(where: { $0.value == value })?.disabled == true {
            return BatchTagPendingState(
                input: input,
                pendingTags: pendingTags,
                fieldError: L10n.string("Tag store is read-only.")
            )
        }
        return BatchTagPendingState(input: "", pendingTags: pendingTags + [value], fieldError: nil)
    }

    static func pendingChips(pendingTags: [String], disabledReason: String?) -> [BatchPendingTagChip] {
        var seenTags: Set<String> = []
        return pendingTags.map { tag in
            guard disabledReason == nil else {
                return BatchPendingTagChip(
                    value: tag,
                    status: .blocked,
                    message: L10n.string("Tag store is read-only.")
                )
            }
            guard let normalized = TagInputNormalization.normalizedValue(tag) else {
                return BatchPendingTagChip(value: tag, status: .invalid, message: TagInputNormalization.invalidMessage)
            }
            if seenTags.contains(normalized) {
                return BatchPendingTagChip(
                    value: tag,
                    status: .alreadySelected,
                    message: L10n.string("Tag already selected.")
                )
            }
            seenTags.insert(normalized)
            return BatchPendingTagChip(value: normalized, status: .ready, message: nil)
        }
    }

    static func visibleCandidates(
        input: String,
        catalog: TagSetSnapshot?,
        pendingTags: [String]
    ) -> [TagRecordSnapshot] {
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

    static func canApply(_ eligibility: BatchTagApplyEligibility) -> Bool {
        guard !eligibility.isApplying,
              eligibility.selectedCount > 0,
              eligibility.disabledReason == nil,
              !eligibility.pendingTags.isEmpty,
              eligibility.fieldError == nil else {
            return false
        }
        guard eligibility.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return pendingChips(
            pendingTags: eligibility.pendingTags,
            disabledReason: eligibility.disabledReason
        ).allSatisfy { !$0.status.preventsApply }
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
            return await BatchAddTagsApplyResult(
                report: nil,
                failure: errorMapper.mapError(error)
            )
        }
    }
}
