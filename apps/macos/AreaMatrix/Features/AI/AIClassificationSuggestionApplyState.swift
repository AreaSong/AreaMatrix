import Combine
import Foundation

func aiCallLogFeatureLabel(_ feature: AICallLogFeatureSnapshot) -> String {
    switch feature {
    case .classification: L10n.string("Classification")
    case .summary: L10n.string("Summary")
    case .tags: L10n.string("Tags")
    case .semanticSearch: L10n.string("Semantic search")
    case .providerTest: L10n.string("Provider Test")
    }
}

func aiCallLogRouteLabel(_ route: AICallLogRouteSnapshot) -> String {
    switch route {
    case .local: L10n.string("Local")
    case .remote: L10n.string("Remote")
    }
}

func aiCallLogStatusLabel(_ status: AICallLogStatusSnapshot) -> String {
    switch status {
    case .success: L10n.string("Success")
    case .failed: L10n.string("Failed")
    case .skipped: L10n.string("Skipped")
    case .unavailable: L10n.string("Unavailable")
    }
}

func aiCallLogSentFieldLabel(_ field: AICallLogSentFieldSnapshot) -> String {
    switch field {
    case .fileName: L10n.string("filename")
    case .repoRelativePath: L10n.string("repo-relative path")
    case .extension: L10n.string("extension")
    case .extractedTextExcerpt: L10n.string("extracted text excerpt")
    case .aiSummary: L10n.string("AI summary")
    case .noteSummary: L10n.string("note summary")
    case .tagCategoryContext: L10n.string("tag/category context")
    }
}

func sentFieldSummary(_ fields: [AICallLogSentFieldSnapshot]) -> String {
    fields.isEmpty ? L10n.string("none") : fields.map(aiCallLogSentFieldLabel).joined(separator: ", ")
}

func fileBatchLabel(_ record: AICallLogRecordSnapshot) -> String {
    if record.feature == .providerTest { return L10n.string("None") }
    if let name = record.fileDisplayName { return name }
    if let batch = record.batchId { return batch }
    return record.scope ?? L10n.string("None")
}

func privacyMatchLabel(_ record: AICallLogRecordSnapshot) -> String {
    let rule = record.privacyRuleName ?? record.privacyRuleId
    let field = record.matchedFieldType.map(aiCallLogSentFieldLabel)
    let text = [rule, field].compactMap { $0 }.joined(separator: " - ")
    return text.isEmpty ? L10n.string("None") : text
}

func rowAccessibility(_ record: AICallLogRecordSnapshot) -> String {
    [
        "\(record.occurredAt)",
        aiCallLogFeatureLabel(record.feature),
        record.route.map(aiCallLogRouteLabel) ?? L10n.string("No route"),
        aiCallLogStatusLabel(record.status),
        record.route == .remote ? L10n.string("Remote") : nil,
        record.status == .skipped ? L10n.string("Skipped") : nil
    ].compactMap { $0 }.joined(separator: ", ")
}

struct AICallLogRowPresentation: Equatable {
    var time: String
    var feature: String
    var provider: String
    var remote: String
    var scope: String
    var status: String
    var duration: String
    var result: String

    init(record: AICallLogRecordSnapshot) {
        time = "\(record.occurredAt)"
        feature = aiCallLogFeatureLabel(record.feature)
        provider = record.providerName ?? record.route.map(aiCallLogRouteLabel) ?? L10n.string("Not recorded")
        remote = record.route == .remote ? L10n.string("Remote") : "-"
        scope = record.scope ?? L10n.string("Not recorded")
        status = aiCallLogStatusLabel(record.status)
        duration = record.durationMs.map { "\($0) ms" } ?? "-"
        result = record.resultSummary
    }
}

enum AICallLogDateRangePreset: Equatable {
    case any
    case last7Days
    case last30Days
    case thisYear
}

enum AICallLogPageState: Equatable {
    case idle
    case loading
    case loaded(AICallLogPageSnapshot)
    case failed(AISettingsError)
}

@MainActor
final class AICallLogModel: ObservableObject {
    @Published private(set) var state: AICallLogPageState = .idle
    @Published private(set) var actionError: AISettingsError?
    @Published private(set) var toastMessage: LocalizedMessage?
    @Published private(set) var isMutating = false
    @Published var featureFilter: AICallLogFeatureSnapshot?
    @Published var routeFilter: AICallLogRouteSnapshot?
    @Published var statusFilter: AICallLogStatusSnapshot?
    @Published private(set) var dateRangePreset: AICallLogDateRangePreset = .any
    @Published private(set) var occurredAfter: Int64?
    @Published private(set) var occurredBefore: Int64?
    @Published var searchQuery = ""
    @Published var selectedRecordIDs: Set<Int64> = []

    let repoPath: String
    private let lister: any CoreAICallLogListing
    private let clearer: any CoreAICallLogClearing
    private let errorMapper: any CoreErrorMapping

    init(
        repoPath: String,
        lister: any CoreAICallLogListing,
        clearer: any CoreAICallLogClearing,
        errorMapper: any CoreErrorMapping
    ) {
        self.repoPath = repoPath
        self.lister = lister
        self.clearer = clearer
        self.errorMapper = errorMapper
    }

    var page: AICallLogPageSnapshot? {
        guard case let .loaded(page) = state else { return nil }
        return page
    }

    var records: [AICallLogRecordSnapshot] {
        page?.records ?? []
    }

    var selectedRecord: AICallLogRecordSnapshot? {
        records.first { selectedRecordIDs.contains($0.id) }
    }

    var isLoading: Bool {
        if case .loading = state { return true }; return false
    }

    var hasLoadedRecords: Bool {
        !(page?.records.isEmpty ?? true)
    }

    var canMutate: Bool {
        !isLoading && !isMutating && hasLoadedRecords
    }

    var deleteDisabledReason: String? {
        selectedRecordIDs.isEmpty ? L10n.string("Select log entries to delete") : nil
    }

    var hasActiveFilters: Bool {
        featureFilter != nil ||
            routeFilter != nil ||
            statusFilter != nil ||
            occurredAfter != nil ||
            occurredBefore != nil ||
            !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var dateRangeSummary: String {
        switch dateRangePreset {
        case .any: L10n.string("Date range: Any")
        case .last7Days: L10n.string("Date range: Last 7 days")
        case .last30Days: L10n.string("Date range: Last 30 days")
        case .thisYear: L10n.string("Date range: This year")
        }
    }

    var emptyStateTitle: String {
        hasActiveFilters
            ? L10n.string("No AI calls match these filters.")
            : L10n.string("No AI calls yet")
    }

    var emptyStateDescription: String {
        hasActiveFilters
            ? L10n.string("Adjust the current filters or clear them.")
            : L10n.string("AI is off by default or has not been used yet.")
    }

    var emptyStateActionTitle: String? {
        hasActiveFilters ? L10n.string("Clear filters") : nil
    }

    var deleteConfirmationTitle: String {
        selectedRecordIDs.count == 1 ?
            L10n.string("Delete this AI call log entry?") :
            L10n.string("Delete selected AI call log entries?")
    }

    var exportDisabledReason: String? {
        if isLoading { return L10n.string("AI call log is loading") }
        if case .failed = state { return L10n.string("AI call log could not be loaded") }
        if !hasLoadedRecords { return L10n.string("No AI call log entries to export") }
        return L10n.string("Use the export flow to save a redacted copy of the AI call log.")
    }

    func load() async {
        guard !isLoading else { return }
        state = .loading
        actionError = nil
        do {
            let loaded = try await lister.listAICalls(
                repoPath: repoPath,
                filter: currentFilter,
                pagination: AICallLogPaginationSnapshot(limit: 100, offset: 0)
            )
            selectedRecordIDs = selectedRecordIDs.intersection(Set(loaded.records.map(\.id)))
            state = .loaded(loaded)
        } catch {
            selectedRecordIDs = []
            state = await .failed(callLogError(for: error))
        }
    }

    func clearFilters() async {
        featureFilter = nil
        routeFilter = nil
        statusFilter = nil
        dateRangePreset = .any
        occurredAfter = nil
        occurredBefore = nil
        searchQuery = ""
        selectedRecordIDs = []
        await load()
    }

    func applyDatePreset(_ preset: AICallLogDateRangePreset, now: Date = Date()) async {
        dateRangePreset = preset
        applyDateBounds(preset, now: now)
        selectedRecordIDs = []
        await load()
    }

    func clearAll() async {
        await performClear(
            request: AICallLogClearRequestSnapshot(scope: .all, entryIds: [], olderThan: nil),
            toast: L10n.message("AI call log cleared.")
        )
    }

    func deleteSelected() async {
        guard !selectedRecordIDs.isEmpty else { return }
        await performClear(
            request: AICallLogClearRequestSnapshot(
                scope: .selectedEntries,
                entryIds: selectedRecordIDs.sorted(),
                olderThan: nil
            ),
            toast: L10n.message("AI log entries deleted.")
        )
    }

    private var currentFilter: AICallLogFilterSnapshot {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return AICallLogFilterSnapshot(
            feature: featureFilter,
            route: routeFilter,
            status: statusFilter,
            occurredAfter: occurredAfter,
            occurredBefore: occurredBefore,
            searchQuery: query.isEmpty ? nil : query
        )
    }

    private func applyDateBounds(_ preset: AICallLogDateRangePreset, now: Date) {
        switch preset {
        case .any:
            occurredAfter = nil
            occurredBefore = nil
        case .last7Days:
            occurredAfter = unixSeconds(daysBefore: 7, now: now)
            occurredBefore = nil
        case .last30Days:
            occurredAfter = unixSeconds(daysBefore: 30, now: now)
            occurredBefore = nil
        case .thisYear:
            occurredAfter = Calendar.current.dateInterval(of: .year, for: now).map { unixSeconds(for: $0.start) }
            occurredBefore = nil
        }
    }

    private func unixSeconds(daysBefore days: Int, now: Date) -> Int64? {
        Calendar.current.date(byAdding: .day, value: -days, to: now).map(unixSeconds(for:))
    }

    private func unixSeconds(for date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970.rounded(.down))
    }

    private func performClear(request: AICallLogClearRequestSnapshot, toast: LocalizedMessage) async {
        guard canMutate else { return }
        isMutating = true
        actionError = nil
        defer { isMutating = false }
        do {
            _ = try await clearer.clearAICallLog(repoPath: repoPath, request: request)
            selectedRecordIDs = []
            toastMessage = toast
            await load()
        } catch {
            actionError = await callLogError(for: error)
        }
    }

    private func callLogError(for error: Error) async -> AISettingsError {
        if let mapping = await errorMapper.mapCoreErrorIfPresent(error) {
            return AISettingsError(
                message: L10n.message("AI call log could not be loaded."),
                recovery: mapping.recoveryMessage(fallback: L10n.message("Retry")),
                detail: mapping.userMessage
            )
        }
        return AISettingsError(
            message: L10n.message("AI call log could not be loaded."),
            recovery: L10n.message("Retry"),
            detail: error.localizedDescription
        )
    }
}

// swiftlint:disable:next type_name
enum AIClassificationSuggestionRuleReturnStatus: Equatable {
    case cancelled
    case saved
}

struct AIClassificationSuggestionReturnContext: Equatable {
    var appliedCategory: String
    var callLogID: Int64?
    var ruleStatus: AIClassificationSuggestionRuleReturnStatus?

    var message: String {
        switch ruleStatus {
        case .saved:
            L10n.format("ai.classification.applied.ruleSaved", appliedCategory)
        case .cancelled:
            L10n.format("ai.classification.applied.ruleNotSaved", appliedCategory)
        case nil:
            L10n.format("ai.classification.applied", appliedCategory)
        }
    }
}

struct AIClassificationSuggestionApplyRequest: Equatable {
    var fileID: Int64
    var targetCategory: String
    var moveFile: Bool
    var rememberRule: Bool
    var suggestion: AIClassificationSuggestionState
    var preview: MoveToCategoryPreviewSnapshot
}

struct ClassifierRuleAIProvenance: Equatable {
    var suggestedCategory: String
    var finalCategory: String
    var confidence: Float
    var reason: String?
    var usedContext: [String]
    var callLogID: Int64?
    var route: String?
}

extension ClassifierRuleAIProvenance {
    init?(suggestion: AIClassificationSuggestionState, finalCategory: String) {
        guard let suggestedCategory = suggestion.suggestedCategory?.trimmingCharacters(in: .whitespacesAndNewlines),
              !suggestedCategory.isEmpty else { return nil }
        self.suggestedCategory = suggestedCategory
        self.finalCategory = finalCategory
        confidence = suggestion.confidence
        reason = suggestion.reason
        usedContext = suggestion.usedContext.map(\.label)
        callLogID = suggestion.callLogID
        route = suggestion.route?.label
    }

    var confidencePercent: Int {
        Int((min(max(confidence, 0), 1) * 100).rounded())
    }

    var usedContextSummary: String {
        usedContext.isEmpty ? L10n.string("None") : usedContext.joined(separator: ", ")
    }
}
