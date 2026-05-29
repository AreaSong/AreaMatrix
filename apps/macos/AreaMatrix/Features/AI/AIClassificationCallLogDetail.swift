import SwiftUI

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
    private let lister: any CoreAICallLogListing
    private let errorMapper: any CoreErrorMapping

    init(
        repoPath: String,
        callLogID: Int64,
        lister: any CoreAICallLogListing = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge()
    ) {
        self.repoPath = repoPath
        self.callLogID = callLogID
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
                    feature: .classification,
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
        lister: any CoreAICallLogListing = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge(),
        onClose: @escaping () -> Void = {}
    ) {
        _model = StateObject(wrappedValue: AIClassificationCallLogDetailModel(
            repoPath: repoPath,
            callLogID: callLogID,
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
            callRow("Feature", label(for: record.feature))
            callRow("Route", record.route.map(label(for:)) ?? "Not recorded")
            callRow("Provider", record.providerName ?? "Not recorded")
            callRow("Model", record.modelName ?? "Not recorded")
            callRow("Status", label(for: record.status))
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

    private func sentFieldSummary(_ fields: [AiCallLogSentField]) -> String {
        fields.isEmpty ? "None" : fields.map(label(for:)).joined(separator: ", ")
    }

    private func label(for feature: AiCallLogFeature) -> String {
        switch feature {
        case .classification: "Classification"
        case .summary: "Summary"
        case .tags: "Tags"
        case .semanticSearch: "Semantic search"
        case .providerTest: "Provider test"
        }
    }

    private func label(for route: AiCallLogRoute) -> String {
        switch route {
        case .local: "Local"
        case .remote: "Remote"
        }
    }

    private func label(for status: AiCallLogStatus) -> String {
        switch status {
        case .success: "Success"
        case .failed: "Failed"
        case .skipped: "Skipped"
        case .unavailable: "Unavailable"
        }
    }

    private func label(for field: AiCallLogSentField) -> String {
        switch field {
        case .fileName: "File name"
        case .repoRelativePath: "Repository path"
        case .extension: "Extension"
        case .extractedTextExcerpt: "Text excerpt"
        case .aiSummary: "AI summary"
        case .noteSummary: "Note summary"
        case .tagCategoryContext: "Tag/category context"
        }
    }
}
