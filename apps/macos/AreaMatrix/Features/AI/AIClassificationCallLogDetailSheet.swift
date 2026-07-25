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
    let feature: AiCallLogFeature
    private let lister: any CoreAICallLogListing
    private let errorMapper: any CoreErrorMapping

    init(
        repoPath: String,
        callLogID: Int64,
        feature: AiCallLogFeature = .classification,
        lister: any CoreAICallLogListing = AppCoreServices.aiCallLogLister,
        errorMapper: any CoreErrorMapping = AppCoreServices.errorMapper
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
            state = await .failed(callLogError(for: error))
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

struct AIClassificationCallLogDetailSheet: View {
    @EnvironmentObject private var localizer: AppLocalizer
    @StateObject private var model: AIClassificationCallLogDetailModel
    let onClose: () -> Void

    init(
        repoPath: String,
        callLogID: Int64,
        feature: AiCallLogFeature = .classification,
        lister: any CoreAICallLogListing = AppCoreServices.aiCallLogLister,
        errorMapper: any CoreErrorMapping = AppCoreServices.errorMapper,
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
                Button(L10n.string("Close"), action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 580, alignment: .topLeading)
        .task { await model.load() }
        .accessibilityIdentifier("ai-category-suggestion-ai-fallback-core-ai-call-log-detail")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.string("AI Call Detail"))
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text(L10n.format("ai.classification.callLog.title", model.callLogID))
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
            callRow(L10n.string("Route"), record.route.map(aiCallLogRouteLabel) ?? L10n.string("Not recorded"))
            callRow(L10n.string("Provider"), record.providerName ?? L10n.string("Not recorded"))
            callRow(L10n.string("Model"), record.modelName ?? L10n.string("Not recorded"))
            callRow("Status", aiCallLogStatusLabel(record.status))
            callRow("Sent fields", sentFieldSummary(record.sentFields))
            callRow(
                L10n.string("Privacy rule"),
                record.privacyRuleName ?? record.privacyRuleId ?? L10n.string("None")
            )
            callRow("Result", record.resultSummary)
            if let errorCode = record.errorCode {
                callRow("Error", errorCode)
            }
        }
        .accessibilityIdentifier("ai-category-suggestion-ai-fallback-core-ai-call-log-loaded")
    }

    private func notFoundContent(_ callLogID: Int64) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L10n.string("AI call log entry could not be found."), systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(L10n.format("ai.classification.callLog.entryMissing", callLogID))
                .font(.callout)
                .foregroundStyle(.secondary)
            Button(L10n.string("Retry")) { Task { await model.load() } }
        }
        .accessibilityIdentifier("ai-category-suggestion-ai-fallback-core-ai-call-log-not-found")
    }

    private func failureContent(_ error: AISettingsError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(localizer.resolve(error.message), systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
            Text(error.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(localizer.resolve(error.recovery))
                .font(.callout)
                .foregroundStyle(.secondary)
            Button(L10n.string("Retry")) { Task { await model.load() } }
        }
        .accessibilityIdentifier("ai-category-suggestion-ai-fallback-core-ai-call-log-error")
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
