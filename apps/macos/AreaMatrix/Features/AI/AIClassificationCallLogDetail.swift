import SwiftUI

func detailRow(_ label: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text(label)
            .foregroundStyle(.secondary)
            .frame(width: 132, alignment: .leading)
        Text(value)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
    .font(.callout)
}

struct AICallLogView: View {
    @StateObject private var model: AICallLogModel
    @State private var confirmation: AICallLogConfirmation?
    @State private var diagnosticsMessage: String?
    let onClose: () -> Void

    init(
        repoPath: String,
        lister: any CoreAICallLogListing = CoreBridge(),
        clearer: any CoreAICallLogClearing = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge(),
        onClose: @escaping () -> Void = {}
    ) {
        _model = StateObject(wrappedValue: AICallLogModel(
            repoPath: repoPath,
            lister: lister,
            clearer: clearer,
            errorMapper: errorMapper
        ))
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            filters
            feedback
            content
            actions
        }
        .padding(20)
        .frame(width: 1_080, height: 680, alignment: .topLeading)
        .task { await model.load() }
        .confirmationDialog(confirmationTitle, isPresented: confirmationBinding, titleVisibility: .visible) {
            Button("Cancel", role: .cancel) { confirmation = nil }
            Button(confirmationButtonTitle, role: .destructive) { Task { await confirmDestructiveAction() } }
        } message: { Text(confirmationMessage) }
        .accessibilityIdentifier("S3-05-C3-05-ai-call-log")
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("AI Call Log").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Text("Logs older than \(model.page?.retentionDays ?? 90) days are automatically removed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Close", action: onClose).keyboardShortcut(.cancelAction)
        }
    }

    private var filters: some View {
        HStack(alignment: .lastTextBaseline) {
            filterPickers
            dateRangeFilter
            TextField("Search file, provider, or error", text: $model.searchQuery)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 190)
                .onSubmit { Task { await model.load() } }
            Button("Clear filters") { Task { await model.clearFilters() } }
        }
    }

    private var filterPickers: some View {
        Group {
            Picker("Feature", selection: $model.featureFilter) {
                Text("All").tag(AiCallLogFeature?.none)
                ForEach(AICallLogView.featureOptions, id: \.self) {
                    Text(aiCallLogFeatureLabel($0)).tag(Optional($0))
                }
            }.frame(width: 166).onChange(of: model.featureFilter) { _, _ in Task { await model.load() } }
            Picker("Provider", selection: $model.routeFilter) {
                Text("All").tag(AiCallLogRoute?.none)
                Text("Local").tag(Optional(AiCallLogRoute.local))
                Text("Remote").tag(Optional(AiCallLogRoute.remote))
            }.frame(width: 128).onChange(of: model.routeFilter) { _, _ in Task { await model.load() } }
            Picker("Status", selection: $model.statusFilter) {
                Text("All").tag(AiCallLogStatus?.none)
                ForEach(AICallLogView.statusOptions, id: \.self) {
                    Text(aiCallLogStatusLabel($0)).tag(Optional($0))
                }
            }.frame(width: 142).onChange(of: model.statusFilter) { _, _ in Task { await model.load() } }
        }
    }

    private var dateRangeFilter: some View {
        Menu(model.dateRangeSummary) {
            Button("Any") { Task { await model.applyDatePreset(.any) } }
            Button("Last 7 days") { Task { await model.applyDatePreset(.last7Days) } }
            Button("Last 30 days") { Task { await model.applyDatePreset(.last30Days) } }
            Button("This year") { Task { await model.applyDatePreset(.thisYear) } }
        }
        .accessibilityLabel("Date range, \(model.dateRangeSummary)")
    }

    @ViewBuilder
    private var feedback: some View {
        if let error = model.actionError {
            Label(error.detail, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
        } else if let diagnosticsMessage {
            Label(diagnosticsMessage, systemImage: "doc.text.magnifyingglass").foregroundStyle(.secondary)
        } else if let toast = model.toastMessage {
            Label(toast, systemImage: "checkmark.circle").foregroundStyle(.green)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView("Loading AI call log...").frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(error):
            failureContent(error)
        case .loaded:
            if model.records.isEmpty {
                emptyContent
            } else {
                HSplitView { logList; detailPane.frame(minWidth: 300) }.frame(minHeight: 380)
            }
        }
    }

    private var emptyContent: some View {
        ContentUnavailableView {
            Label(model.emptyStateTitle, systemImage: "sparkles")
        } description: {
            Text(model.emptyStateDescription)
        } actions: {
            if model.emptyStateActionTitle != nil {
                Button("Clear filters") { Task { await model.clearFilters() } }
            }
        }
    }

    private func failureContent(_ error: AISettingsError) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle)
            Text("AI call log could not be loaded.").font(.headline)
            Text(error.detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack {
                Button("Retry") { Task { await model.load() } }
                Button("Open diagnostics") { diagnosticsMessage = error.detail }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var logList: some View {
        VStack(spacing: 4) {
            AICallLogHeaderRow()
            List(model.records, id: \.id, selection: $model.selectedRecordIDs) { record in
                AICallLogRow(record: record)
                    .tag(record.id)
                    .accessibilityLabel(rowAccessibility(record))
            }
        }
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let record = model.selectedRecord {
                detailRow("File or batch", fileBatchLabel(record))
                detailRow("Provider", record.providerName ?? record.route.map(aiCallLogRouteLabel) ?? "Not recorded")
                detailRow("Model", record.modelName ?? "Not recorded")
                detailRow("Sent fields", sentFieldSummary(record.sentFields))
                detailRow("Privacy rules checked", record.privacyRulesChecked ? "yes" : "no user content")
                detailRow("Privacy match", privacyMatchLabel(record))
                detailRow("Result summary", record.resultSummary)
                if let code = record.errorCode { detailRow("Error", code) }
            } else {
                Text("Select an AI call to inspect its redacted details.").foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 14)
    }

    private var actions: some View {
        HStack {
            Button("Export redacted log...") {}
                .disabled(model.exportDisabledReason != nil)
                .accessibilityHint(model.exportDisabledReason ?? "")
            Button("Clear log...") { confirmation = .clearAll }.disabled(!model.canMutate)
            Button("Delete selected") { confirmation = .deleteSelected }
                .disabled(!model.canMutate || model.deleteDisabledReason != nil)
                .accessibilityHint(model.deleteDisabledReason ?? "")
            Spacer()
            if model.isMutating { ProgressView("Updating AI call log...") }
        }
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })
    }

    private var confirmationTitle: String {
        if confirmation == .clearAll { return "Clear AI call log?" }
        return model.deleteConfirmationTitle
    }

    private var confirmationButtonTitle: String {
        confirmation == .clearAll ? "Clear log" : "Delete log entries"
    }

    private var confirmationMessage: String {
        if confirmation == .clearAll {
            return """
            This deletes all AI call log entries on this Mac. It will not delete files, \
            AI results, tags, summaries, notes, AI settings, or API keys.
            """
        }
        return """
        This only deletes log entries. It will not delete files, AI results, tags, \
        summaries, notes, or AI settings.
        """
    }

    private func confirmDestructiveAction() async {
        let action = confirmation
        confirmation = nil
        if action == .clearAll { await model.clearAll() } else { await model.deleteSelected() }
    }
}

private enum AICallLogConfirmation: String, Identifiable {
    case clearAll, deleteSelected
    var id: String { rawValue }
}

private struct AICallLogHeaderRow: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("Time").frame(width: 92, alignment: .leading)
            Text("Feature").frame(width: 112, alignment: .leading)
            Text("Provider").frame(width: 118, alignment: .leading)
            Text("Remote").frame(width: 64, alignment: .leading)
            Text("Scope").frame(width: 116, alignment: .leading)
            Text("Status").frame(width: 78, alignment: .leading)
            Text("Duration").frame(width: 70, alignment: .trailing)
            Text("Result").frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
    }
}

private struct AICallLogRow: View {
    let record: AiCallLogRecord
    private var row: AICallLogRowPresentation { AICallLogRowPresentation(record: record) }

    var body: some View {
        HStack(spacing: 8) {
            Text(row.time).frame(width: 92, alignment: .leading)
            Text(row.feature).frame(width: 112, alignment: .leading)
            Text(row.provider).frame(width: 118, alignment: .leading)
            Text(row.remote).frame(width: 64, alignment: .leading)
            Text(row.scope).frame(width: 116, alignment: .leading)
            Text(row.status).frame(width: 78, alignment: .leading)
            Text(row.duration).frame(width: 70, alignment: .trailing)
            Text(row.result).frame(maxWidth: .infinity, alignment: .leading)
        }
        .lineLimit(1)
    }
}

private extension AICallLogView {
    static let featureOptions: [AiCallLogFeature] = [
        .classification,
        .summary,
        .tags,
        .semanticSearch,
        .providerTest
    ]
    static let statusOptions: [AiCallLogStatus] = [.success, .failed, .skipped, .unavailable]
}

enum AIClassificationCallLogDetailState: Equatable {
    case idle
    case loading
    case loaded(AiCallLogRecord)
    case notFound(Int64)
    case failed(AISettingsError)
}

@MainActor
final class AIClassificationCallLogDetailModel: ObservableObject {
    @Published private(set) var state: AIClassificationCallLogDetailState = .idle

    let repoPath: String
    let callLogID: Int64
    let feature: AiCallLogFeature
    private let lister: any CoreAICallLogListing
    private let errorMapper: any CoreErrorMapping

    init(
        repoPath: String,
        callLogID: Int64,
        feature: AiCallLogFeature = .classification,
        lister: any CoreAICallLogListing = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge()
    ) {
        self.repoPath = repoPath
        self.callLogID = callLogID
        self.feature = feature
        self.lister = lister
        self.errorMapper = errorMapper
    }

    var record: AiCallLogRecord? {
        guard case let .loaded(record) = state else { return nil }
        return record
    }

    func load() async {
        guard state != .loading else { return }
        state = .loading
        do {
            let page = try await lister.listAICalls(
                repoPath: repoPath,
                filter: AiCallLogFilter(
                    feature: feature,
                    route: nil,
                    status: nil,
                    occurredAfter: nil,
                    occurredBefore: nil,
                    searchQuery: nil
                ),
                pagination: AiCallLogPagination(limit: 100, offset: 0)
            )
            if let record = page.records.first(where: { $0.id == callLogID }) {
                state = .loaded(record)
            } else {
                state = .notFound(callLogID)
            }
        } catch {
            state = .failed(await callLogError(for: error))
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

struct AIClassificationCallLogDetailSheet: View {
    @StateObject private var model: AIClassificationCallLogDetailModel
    let onClose: () -> Void

    init(
        repoPath: String,
        callLogID: Int64,
        feature: AiCallLogFeature = .classification,
        lister: any CoreAICallLogListing = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge(),
        onClose: @escaping () -> Void = {}
    ) {
        _model = StateObject(wrappedValue: AIClassificationCallLogDetailModel(
            repoPath: repoPath,
            callLogID: callLogID,
            feature: feature,
            lister: lister,
            errorMapper: errorMapper
        ))
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            bodyContent
            HStack {
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 580, alignment: .topLeading)
        .task { await model.load() }
        .accessibilityIdentifier("S3-04-C3-10-ai-call-log-detail")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("AI Call Detail")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text("Call log \(model.callLogID)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView("Loading AI call...")
        case let .loaded(record):
            loadedContent(record)
        case let .notFound(callLogID):
            notFoundContent(callLogID)
        case let .failed(error):
            failureContent(error)
        }
    }

    private func loadedContent(_ record: AiCallLogRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            callRow("Feature", aiCallLogFeatureLabel(record.feature))
            callRow("Route", record.route.map(aiCallLogRouteLabel) ?? "Not recorded")
            callRow("Provider", record.providerName ?? "Not recorded")
            callRow("Model", record.modelName ?? "Not recorded")
            callRow("Status", aiCallLogStatusLabel(record.status))
            callRow("Sent fields", sentFieldSummary(record.sentFields))
            callRow("Privacy rule", record.privacyRuleName ?? record.privacyRuleId ?? "None")
            callRow("Result", record.resultSummary)
            if let errorCode = record.errorCode {
                callRow("Error", errorCode)
            }
        }
        .accessibilityIdentifier("S3-04-C3-10-ai-call-log-loaded")
    }

    private func notFoundContent(_ callLogID: Int64) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("AI call log entry could not be found.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text("Entry \(callLogID) is not present in the current classification call log page.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Retry") { Task { await model.load() } }
        }
        .accessibilityIdentifier("S3-04-C3-10-ai-call-log-not-found")
    }

    private func failureContent(_ error: AISettingsError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error.message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
            Text(error.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(error.recovery)
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Retry") { Task { await model.load() } }
        }
        .accessibilityIdentifier("S3-04-C3-10-ai-call-log-error")
    }

    private func callRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 104, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
        }
        .font(.callout)
    }
}
