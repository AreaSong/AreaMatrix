import Combine
import Foundation

func aiCallLogFeatureLabel(_ feature: AiCallLogFeature) -> String {
    switch feature {
    case .classification: "Classification"
    case .summary: "Summary"
    case .tags: "Tags"
    case .semanticSearch: "Semantic search"
    case .providerTest: "Provider Test"
    }
}

func aiCallLogRouteLabel(_ route: AiCallLogRoute) -> String {
    switch route {
    case .local: "Local"
    case .remote: "Remote"
    }
}

func aiCallLogStatusLabel(_ status: AiCallLogStatus) -> String {
    switch status {
    case .success: "Success"
    case .failed: "Failed"
    case .skipped: "Skipped"
    case .unavailable: "Unavailable"
    }
}

func aiCallLogSentFieldLabel(_ field: AiCallLogSentField) -> String {
    switch field {
    case .fileName: "filename"
    case .repoRelativePath: "repo-relative path"
    case .extension: "extension"
    case .extractedTextExcerpt: "extracted text excerpt"
    case .aiSummary: "AI summary"
    case .noteSummary: "note summary"
    case .tagCategoryContext: "tag/category context"
    }
}

func sentFieldSummary(_ fields: [AiCallLogSentField]) -> String {
    fields.isEmpty ? "none" : fields.map(aiCallLogSentFieldLabel).joined(separator: ", ")
}

func fileBatchLabel(_ record: AiCallLogRecord) -> String {
    if record.feature == .providerTest { return "None" }
    if let name = record.fileDisplayName { return name }
    if let batch = record.batchId { return batch }
    return record.scope ?? "None"
}

func privacyMatchLabel(_ record: AiCallLogRecord) -> String {
    let rule = record.privacyRuleName ?? record.privacyRuleId
    let field = record.matchedFieldType.map(aiCallLogSentFieldLabel)
    let text = [rule, field].compactMap { $0 }.joined(separator: " - ")
    return text.isEmpty ? "None" : text
}

func rowAccessibility(_ record: AiCallLogRecord) -> String {
    [
        "\(record.occurredAt)",
        aiCallLogFeatureLabel(record.feature),
        record.route.map(aiCallLogRouteLabel) ?? "No route",
        aiCallLogStatusLabel(record.status),
        record.route == .remote ? "Remote" : nil,
        record.status == .skipped ? "Skipped" : nil
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

    init(record: AiCallLogRecord) {
        time = "\(record.occurredAt)"
        feature = aiCallLogFeatureLabel(record.feature)
        provider = record.providerName ?? record.route.map(aiCallLogRouteLabel) ?? "Not recorded"
        remote = record.route == .remote ? "Remote" : "-"
        scope = record.scope ?? "Not recorded"
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
    case loaded(AiCallLogPage)
    case failed(AISettingsError)
}

@MainActor
final class AICallLogModel: ObservableObject {
    @Published private(set) var state: AICallLogPageState = .idle
    @Published private(set) var actionError: AISettingsError?
    @Published private(set) var toastMessage: String?
    @Published private(set) var isMutating = false
    @Published var featureFilter: AiCallLogFeature?
    @Published var routeFilter: AiCallLogRoute?
    @Published var statusFilter: AiCallLogStatus?
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
        lister: any CoreAICallLogListing = CoreBridge(),
        clearer: any CoreAICallLogClearing = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge()
    ) {
        self.repoPath = repoPath
        self.lister = lister
        self.clearer = clearer
        self.errorMapper = errorMapper
    }

    var page: AiCallLogPage? {
        guard case let .loaded(page) = state else { return nil }
        return page
    }

    var records: [AiCallLogRecord] {
        page?.records ?? []
    }

    var selectedRecord: AiCallLogRecord? {
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
        selectedRecordIDs.isEmpty ? "Select log entries to delete" : nil
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
        case .any: "Date range: Any"
        case .last7Days: "Date range: Last 7 days"
        case .last30Days: "Date range: Last 30 days"
        case .thisYear: "Date range: This year"
        }
    }

    var emptyStateTitle: String {
        hasActiveFilters ? "No AI calls match these filters." : "No AI calls yet"
    }

    var emptyStateDescription: String {
        // swiftlint:disable:next line_length
        hasActiveFilters ? "Adjust the current filters or clear them." : "AI is off by default or has not been used yet."
    }

    var emptyStateActionTitle: String? {
        hasActiveFilters ? "Clear filters" : nil
    }

    var deleteConfirmationTitle: String {
        selectedRecordIDs.count == 1 ?
            "Delete this AI call log entry?" :
            "Delete selected AI call log entries?"
    }

    var exportDisabledReason: String? {
        if isLoading { return "AI call log is loading" }
        if case .failed = state { return "AI call log could not be loaded" }
        if !hasLoadedRecords { return "No AI call log entries to export" }
        return "Redacted export belongs to the export save-panel capability, not C3-05"
    }

    func load() async {
        guard !isLoading else { return }
        state = .loading
        actionError = nil
        do {
            let loaded = try await lister.listAICalls(
                repoPath: repoPath,
                filter: currentFilter,
                pagination: AiCallLogPagination(limit: 100, offset: 0)
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
            request: AiCallLogClearRequest(scope: .all, entryIds: [], olderThan: nil),
            toast: "AI call log cleared."
        )
    }

    func deleteSelected() async {
        guard !selectedRecordIDs.isEmpty else { return }
        await performClear(
            request: AiCallLogClearRequest(
                scope: .selectedEntries,
                entryIds: selectedRecordIDs.sorted(),
                olderThan: nil
            ),
            toast: "AI log entries deleted."
        )
    }

    private var currentFilter: AiCallLogFilter {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return AiCallLogFilter(
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

    private func performClear(request: AiCallLogClearRequest, toast: String) async {
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
        if let coreError = error as? CoreError {
            let mapping = await errorMapper.mapCoreError(coreError)
            return AISettingsError(
                message: "AI call log could not be loaded.",
                recovery: mapping.suggestedAction.isEmpty ? "Retry" : mapping.suggestedAction,
                detail: mapping.userMessage
            )
        }
        return AISettingsError(
            message: "AI call log could not be loaded.",
            recovery: "Retry",
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
            "Classification applied to \(appliedCategory). Rule saved for future imports."
        case .cancelled:
            "Classification applied to \(appliedCategory). Rule was not saved."
        case nil:
            "Classification applied to \(appliedCategory)."
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
        usedContext.isEmpty ? "None" : usedContext.joined(separator: ", ")
    }
}
