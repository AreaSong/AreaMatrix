import SwiftUI

enum AISummaryEditorStatus: Equatable {
    case empty, draft, saved, dirty
    case skipped(AiSummarySkipReason?)
    case unavailable(AiSummarySkipReason?)

    var label: String {
        switch self {
        case .empty: "No AI summary yet."
        case .draft: "Draft"
        case .saved: "Saved"
        case .dirty: "Unsaved changes"
        case let .skipped(reason): reason.map(aiSummarySkipReasonLabel) ?? "Skipped"
        case .unavailable: "Summary unavailable"
        }
    }
}

enum AISummaryEditorOperation: Equatable {
    case idle, generating, saving, clearing, failed(AISettingsError)
    var isBusy: Bool { self == .generating || self == .saving || self == .clearing }
}

struct AISummaryProvenance: Equatable {
    var draftID: String?
    var route: AiSummaryRoute?
    var modelName: String?
    var generatedAt: Int64?
    var usedContext: [AiSummaryInputField]
    var privacyRuleID: String?
    var callLogID: Int64?
    var characterCount: Int64

    init(draft: AiSummaryDraft) {
        draftID = draft.draftId; route = draft.route; modelName = draft.modelName
        generatedAt = draft.generatedAt; usedContext = draft.usedContext
        privacyRuleID = draft.privacyRuleId; callLogID = draft.callLogId
        characterCount = draft.characterCount
    }

    init(report: AiSummarySaveReport) {
        draftID = nil; route = report.route; modelName = report.modelName
        generatedAt = report.generatedAt; usedContext = report.usedContext
        privacyRuleID = report.privacyRuleId; callLogID = report.callLogId
        characterCount = report.characterCount
    }
}

private struct AISummaryEditorSnapshot {
    var draftText: String
    var savedText: String?
    var baselineText: String?
    var provenance: AISummaryProvenance?
    var status: AISummaryEditorStatus
}

@MainActor
final class AISummaryEditorModel: ObservableObject {
    @Published private(set) var status: AISummaryEditorStatus = .empty
    @Published private(set) var operation: AISummaryEditorOperation = .idle
    @Published private(set) var provenance: AISummaryProvenance?
    @Published var draftText = ""

    let repoPath: String
    private(set) var fileID: Int64
    private let summaryStore: any CoreAISummaryManaging
    private let errorMapper: any CoreErrorMapping
    private var savedText: String?
    private var baselineText: String?
    private var generationToken = UUID()
    private var generationSnapshot: AISummaryEditorSnapshot?

    init(
        repoPath: String,
        fileID: Int64,
        summaryStore: any CoreAISummaryManaging = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge()
    ) {
        self.repoPath = repoPath; self.fileID = fileID
        self.summaryStore = summaryStore; self.errorMapper = errorMapper
    }

    var characterCountText: String { "\(draftText.count) characters" }
    var canGenerate: Bool { !operation.isBusy }
    var canCancelGeneration: Bool { operation == .generating }
    var canRegenerate: Bool { canGenerate && (!draftText.isEmpty || savedText != nil || provenance != nil) }
    var canDiscard: Bool { canGenerate && (status == .dirty || status == .draft) }
    var canClear: Bool { canGenerate && (!draftText.isEmpty || savedText != nil || provenance != nil) }
    var canSave: Bool {
        canGenerate && !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (status == .dirty || status == .draft)
    }

    func reset(fileID: Int64) {
        guard self.fileID != fileID else { return }
        self.fileID = fileID; draftText = ""; savedText = nil; baselineText = nil; provenance = nil
        status = .empty; operation = .idle; generationToken = UUID()
    }

    func updateDraft(_ text: String) {
        guard draftText != text else { return }
        draftText = text
        if text.isEmpty, savedText == nil, provenance == nil { status = .empty }
        else if text == baselineText, savedText != nil { status = .saved }
        else if text == baselineText { status = .draft }
        else { status = .dirty }
    }

    func generate(regenerate: Bool) async {
        guard canGenerate else { return }
        let token = UUID(); generationToken = token; generationSnapshot = snapshot(); operation = .generating
        do {
            let draft = try await summaryStore.generateAISummary(repoPath: repoPath, request: generationRequest(regenerate))
            guard token == generationToken else { return }
            operation = .idle; apply(draft)
        } catch {
            guard token == generationToken else { return }
            operation = .failed(await summaryError(for: error, message: "Summary could not be generated."))
        }
    }

    func cancelGeneration() {
        guard canCancelGeneration else { return }
        generationToken = UUID()
        if let generationSnapshot { restore(generationSnapshot) }
        operation = .idle
    }

    func save() async {
        guard canSave else { return }
        operation = .saving
        do {
            let report = try await summaryStore.saveAISummary(repoPath: repoPath, request: saveRequest())
            savedText = report.savedSummary; draftText = report.savedSummary; baselineText = report.savedSummary
            provenance = AISummaryProvenance(report: report); status = .saved; operation = .idle
        } catch {
            operation = .failed(await summaryError(for: error, message: "Summary could not be saved."))
        }
    }

    func discardChanges() {
        guard canDiscard else { return }
        draftText = savedText ?? ""; baselineText = savedText; status = savedText == nil ? .empty : .saved
    }

    func clear() async {
        guard canClear else { return }
        operation = .clearing
        do {
            _ = try await summaryStore.clearAISummary(
                repoPath: repoPath,
                request: AiSummaryClearRequest(fileId: fileID, confirmed: true)
            )
            draftText = ""; savedText = nil; baselineText = nil; provenance = nil; status = .empty; operation = .idle
        } catch {
            operation = .failed(await summaryError(for: error, message: "Summary could not be cleared."))
        }
    }

    private func generationRequest(_ regenerate: Bool) -> AiSummaryGenerationRequest {
        AiSummaryGenerationRequest(
            fileId: fileID,
            providerScope: .localPreferred,
            contextPolicy: .metadataAndExtractedText,
            privacyPolicyRef: nil,
            regenerateExisting: regenerate
        )
    }

    private func apply(_ draft: AiSummaryDraft) {
        provenance = AISummaryProvenance(draft: draft)
        switch draft.status {
        case .draft:
            let text = draft.summaryText ?? ""; draftText = text; baselineText = text; status = .draft
        case .skipped:
            status = .skipped(draft.skippedReason)
        case .unavailable:
            status = .unavailable(draft.skippedReason)
        }
    }

    private func saveRequest() -> AiSummarySaveRequest {
        AiSummarySaveRequest(
            fileId: fileID,
            summaryText: draftText,
            draftId: provenance?.draftID,
            route: provenance?.route,
            modelName: provenance?.modelName,
            generatedAt: provenance?.generatedAt,
            usedContext: provenance?.usedContext ?? [],
            privacyRuleId: provenance?.privacyRuleID,
            callLogId: provenance?.callLogID,
            editedByUser: status == .dirty
        )
    }

    private func snapshot() -> AISummaryEditorSnapshot {
        AISummaryEditorSnapshot(
            draftText: draftText,
            savedText: savedText,
            baselineText: baselineText,
            provenance: provenance,
            status: status
        )
    }

    private func restore(_ snapshot: AISummaryEditorSnapshot) {
        draftText = snapshot.draftText; savedText = snapshot.savedText; baselineText = snapshot.baselineText
        provenance = snapshot.provenance; status = snapshot.status
    }

    private func summaryError(for error: Error, message: String) async -> AISettingsError {
        guard let coreError = error as? CoreError else {
            return AISettingsError(message: message, recovery: "Retry or return to detail.", detail: error.localizedDescription)
        }
        let mapping = await errorMapper.mapCoreError(coreError)
        return AISettingsError(
            message: message,
            recovery: mapping.suggestedAction.isEmpty ? "Retry or return to detail." : mapping.suggestedAction,
            detail: mapping.userMessage
        )
    }
}

struct SearchIndexingStatusRouteView: View {
    let request: SearchQueryRequestSnapshot
    let indexStatus: SearchIndexStatusSnapshot?
    let onRetry: () -> Void
    let onClose: () -> Void

    var body: some View {
        MainFileActionSheetContainer(title: "Search Index Status", pageID: "S2-01-indexing-status") {
            Label(statusText, systemImage: "exclamationmark.triangle")
                .font(.callout)
            metadataRow("Query", request.query)
            metadataRow("Scope", request.scope.displayName)
            HStack {
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button("Retry", action: onRetry)
            }
        }
        .accessibilityIdentifier("S2-01-indexing-status-search-route")
    }

    private var statusText: String {
        switch indexStatus {
        case .unavailable:
            "Search index unavailable"
        case .indexing:
            "Search index is updating"
        case .ready:
            "Search index ready"
        case nil:
            "Search index status unavailable"
        }
    }
}

func searchContextText(_ request: SearchQueryRequestSnapshot) -> String {
    "Scope: \(request.scope.displayName) | Sort: \(request.sort.displayName)"
}

struct AISummaryEditor: View {
    @StateObject private var model: AISummaryEditorModel
    @State private var confirmation: AISummaryConfirmation?
    @FocusState private var isEditorFocused: Bool

    init(repoPath: String, fileID: Int64) {
        _model = StateObject(wrappedValue: AISummaryEditorModel(repoPath: repoPath, fileID: fileID))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            provenanceRows
            editor
            errorView
            controls
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
        .confirmationDialog(
            confirmation?.title ?? "",
            isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
            titleVisibility: .visible
        ) {
            Button("Cancel", role: .cancel) { confirmation = nil }
            Button(confirmation?.actionTitle ?? "", role: confirmation?.role) { performConfirmedAction() }
        } message: {
            Text(confirmation?.message ?? "")
        }
        .accessibilityIdentifier("S3-06-C3-06-ai-summary-editor")
    }

    private var header: some View {
        HStack {
            Text("AI Summary").font(.headline).accessibilityAddTraits(.isHeader)
            Text(model.status.label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            Text(model.characterCountText).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var provenanceRows: some View {
        if let provenance = model.provenance {
            VStack(alignment: .leading, spacing: 4) {
                Text(provenance.route.map(aiSummaryRouteLabel) ?? "Draft")
                Text("Model: \(provenance.modelName ?? "Not recorded")")
                Text("Used fields: \(summaryUsedFields(provenance.usedContext))")
                if let generatedAt = provenance.generatedAt {
                    Text("Generated: \(generatedAt)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("S3-06-C3-06-provenance")
        }
    }

    private var editor: some View {
        TextEditor(text: Binding(get: { model.draftText }, set: model.updateDraft))
            .font(.body)
            .frame(minHeight: 150)
            .overlay(alignment: .topLeading) {
                if model.draftText.isEmpty {
                    Text("No AI summary yet.").foregroundStyle(.secondary).padding(.top, 8).padding(.leading, 5)
                }
            }
            .disabled(model.operation.isBusy)
            .focused($isEditorFocused)
            .accessibilityLabel("AI summary draft")
    }

    @ViewBuilder
    private var errorView: some View {
        if case let .failed(error) = model.operation {
            VStack(alignment: .leading, spacing: 4) {
                Label(error.message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                Text(error.detail).font(.caption).foregroundStyle(.secondary)
                Text(error.recovery).font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("S3-06-C3-06-error")
        }
    }

    private var controls: some View {
        HStack {
            Button("Generate summary") { Task { await model.generate(regenerate: false) } }
                .disabled(!model.canGenerate)
            Button("Regenerate...") { confirmation = .regenerate }
                .disabled(!model.canRegenerate)
            if model.canCancelGeneration {
                Button("Cancel generation", action: model.cancelGeneration)
            }
            Spacer()
            Button("Discard changes", action: model.discardChanges).disabled(!model.canDiscard)
            Button("Clear summary...") { confirmation = .clear }.disabled(!model.canClear)
            Button(saveTitle) { Task { await model.save() } }.disabled(!model.canSave)
        }
    }

    private var saveTitle: String {
        model.operation == .saving ? "Saving summary..." : "Save"
    }

    private func performConfirmedAction() {
        let action = confirmation
        confirmation = nil
        switch action {
        case .regenerate:
            Task { await model.generate(regenerate: true) }
        case .clear:
            Task { await model.clear() }
        case nil:
            break
        }
    }
}

private enum AISummaryConfirmation {
    case regenerate, clear

    var title: String {
        switch self {
        case .regenerate: "Regenerate AI summary?"
        case .clear: "Clear AI summary?"
        }
    }

    var message: String {
        switch self {
        case .regenerate:
            "This replaces the current draft or unsaved edits with a new AI-generated draft. Saved notes and the original file will not be changed."
        case .clear:
            "This clears the AI-derived summary for this file. It will not delete your note, original file, extracted text, tags, or AI call log."
        }
    }

    var actionTitle: String {
        switch self {
        case .regenerate: "Regenerate"
        case .clear: "Clear summary"
        }
    }

    var role: ButtonRole? {
        self == .clear ? .destructive : nil
    }
}

private func summaryUsedFields(_ fields: [AiSummaryInputField]) -> String {
    fields.isEmpty ? "none" : fields.map(aiSummaryInputFieldLabel).joined(separator: ", ")
}

func aiSummaryRouteLabel(_ route: AiSummaryRoute) -> String {
    switch route {
    case .local: "Generated locally"
    case .remote: "Generated remotely"
    }
}

func aiSummaryInputFieldLabel(_ field: AiSummaryInputField) -> String {
    switch field {
    case .fileName: "filename"
    case .repoRelativePath: "repo-relative path"
    case .extractedTextExcerpt: "extracted text"
    case .existingAiSummary: "existing AI summary"
    case .noteSummary: "note summary"
    case .tagCategoryContext: "tag/category context"
    }
}

func aiSummarySkipReasonLabel(_ reason: AiSummarySkipReason) -> String {
    switch reason {
    case .aiDisabled: "AI summaries are off"
    case .featureDisabled: "Auto summaries are off"
    case .providerUnavailable: "AI provider is unavailable"
    case .privacyRule: "Skipped by privacy rule"
    case .noEligibleInput: "No eligible summary input"
    case .callLogUnavailable: "AI call log is unavailable"
    }
}

extension LocalModelAvailability {
    init(snapshotAvailability: LocalModelAvailabilityState) {
        switch snapshotAvailability {
        case .unknown: self = .unknown
        case .ready: self = .ready
        case .notInstalled: self = .notInstalled
        case .pathUnreadable: self = .pathUnreadable
        case .versionIncompatible: self = .versionIncompatible
        case .checking: self = .checking
        case .verifying: self = .verifying
        case .loading: self = .loading
        case .corrupted: self = .corrupted
        case .runtimeFailed: self = .runtimeFailed
        case .error: self = .error
        }
    }
}

extension LocalModelRecommendedAction {
    init(snapshotAction: LocalModelRecommendedActionState) {
        switch snapshotAction {
        case .none: self = .none
        case .checkStatus: self = .checkStatus
        case .retryStatusCheck: self = .retryStatusCheck
        case .openInstallHelp: self = .openInstallHelp
        case .openModelLocation: self = .openModelLocation
        case .runHealthCheck: self = .runHealthCheck
        case .repairMetadata: self = .repairMetadata
        case .openDiagnostics: self = .openDiagnostics
        case .useNonAiFallback: self = .useNonAiFallback
        }
    }
}
