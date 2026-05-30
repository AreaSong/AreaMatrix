import SwiftUI

@MainActor
final class AISummaryEditorModel: ObservableObject {
    @Published private(set) var status: AISummaryEditorStatus = .empty
    @Published private(set) var operation: AISummaryEditorOperation = .idle
    @Published private(set) var provenance: AISummaryProvenance?
    @Published var draftText = ""

    let repoPath: String
    private(set) var fileID: Int64
    private let summaryStore: any CoreAISummaryManaging
    private let privacyRules: any CoreAIPrivacyEvaluating
    private let errorMapper: any CoreErrorMapping
    private let summaryProviderScope: AiSummaryProviderScope
    private var privacyContext: AISummaryPrivacyContext
    private var savedText: String?
    private var baselineText: String?
    private var generationToken = UUID()
    private var generationSnapshot: AISummaryEditorSnapshot?
    private(set) var privacySkip: AISummaryPrivacySkip?

    init(
        repoPath: String,
        fileID: Int64,
        summaryStore: any CoreAISummaryManaging = CoreBridge(),
        privacyRules: any CoreAIPrivacyEvaluating = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge(),
        summaryProviderScope: AiSummaryProviderScope = .localPreferred,
        privacyContext: AISummaryPrivacyContext = AISummaryPrivacyContext()
    ) {
        self.repoPath = repoPath; self.fileID = fileID
        self.summaryStore = summaryStore; self.privacyRules = privacyRules; self.errorMapper = errorMapper
        self.summaryProviderScope = summaryProviderScope
        self.privacyContext = privacyContext
    }

    var characterCountText: String { "\(draftText.count) characters" }
    var canGenerate: Bool { !operation.isBusy }
    var canCancelGeneration: Bool { operation == .generating }
    var canRegenerate: Bool { canGenerate && (!draftText.isEmpty || savedText != nil || provenance != nil) }
    var canDiscard: Bool { canGenerate && (status == .dirty || status == .draft) }
    var canClear: Bool {
        canGenerate && privacySkip == nil && (!draftText.isEmpty || savedText != nil || provenance != nil)
    }
    var canSave: Bool {
        canGenerate && !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (status == .dirty || status == .draft)
    }

    func reset(fileID: Int64) {
        guard self.fileID != fileID else { return }
        self.fileID = fileID; draftText = ""; savedText = nil; baselineText = nil; provenance = nil
        privacySkip = nil; status = .empty; operation = .idle; generationToken = UUID()
    }

    func updatePrivacyContext(_ context: AISummaryPrivacyContext) { privacyContext = context }

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
            if let privacySkip = try await skippedByPrivacyRules() {
                guard token == generationToken else { return }
                let draft = try await loggedPrivacySkipDraft(privacySkip, regenerate: regenerate)
                guard token == generationToken else { return }
                apply(privacySkip, draft: draft); operation = .idle; return
            }
            let draft = try await summaryStore.generateAISummary(
                repoPath: repoPath,
                request: generationRequest(regenerate)
            )
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
            draftText = ""; savedText = nil; baselineText = nil; provenance = nil; privacySkip = nil
            status = .empty; operation = .idle
        } catch {
            operation = .failed(await summaryError(for: error, message: "Summary could not be cleared."))
        }
    }

    private func generationRequest(
        _ regenerate: Bool,
        privacyPolicyRef: String? = nil
    ) -> AiSummaryGenerationRequest {
        AiSummaryGenerationRequest(
            fileId: fileID,
            providerScope: summaryProviderScope,
            contextPolicy: .metadataAndExtractedText,
            privacyPolicyRef: privacyPolicyRef,
            regenerateExisting: regenerate
        )
    }

    private func skippedByPrivacyRules() async throws -> AISummaryPrivacySkip? {
        let snapshot = try await privacyRules.loadAIPrivacyRules(repoPath: repoPath)
        let report = try await privacyRules.evaluateAIPrivacy(
            repoPath: repoPath,
            request: privacyEvaluationRequest(snapshot: snapshot)
        )
        guard report.decision != .allowed else { return nil }
        return AISummaryPrivacySkip(report: report)
    }

    private func privacyEvaluationRequest(snapshot: AiPrivacyRulesSnapshot) -> AiPrivacyEvaluationRequest {
        AiPrivacyEvaluationRequest(
            feature: .autoSummaries,
            route: AiPrivacyEvaluationRoute(summaryProviderScope: summaryProviderScope),
            requestedFields: [.fileName, .repoRelativePath, .extractedTextExcerpt],
            privacyGateEnabled: snapshot.privacyGateEnabled,
            providerScope: snapshot.providerScope,
            rules: snapshot.rules.map(AiPrivacyRuleInput.init(summaryRule:)),
            remoteAllowedFields: snapshot.remoteAllowedFields.map(AiPrivacyFieldRule.init(state:)),
            context: privacyEvaluationContext()
        )
    }

    private func privacyEvaluationContext() -> AiPrivacyEvaluationContext {
        var context = privacyContext.coreContext
        context.fileId = fileID; return context
    }

    private func loggedPrivacySkipDraft(
        _ skip: AISummaryPrivacySkip,
        regenerate: Bool
    ) async throws -> AiSummaryDraft {
        guard let policyRef = skip.privacyPolicyRefForSummaryLog else {
            return skip.unloggedDraft(fileID: fileID)
        }
        return try await summaryStore.generateAISummary(
            repoPath: repoPath,
            request: generationRequest(regenerate, privacyPolicyRef: policyRef)
        )
    }

    private func apply(_ draft: AiSummaryDraft) {
        privacySkip = nil
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

    private func apply(_ skip: AISummaryPrivacySkip, draft: AiSummaryDraft) {
        privacySkip = skip
        provenance = AISummaryProvenance(draft: draft)
        status = skip.editorStatus
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
            return AISettingsError(
                message: message,
                recovery: "Retry or return to detail.",
                detail: error.localizedDescription
            )
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
    private let repoPath: String
    private let fileID: Int64
    private let privacyContext: AISummaryPrivacyContext
    @StateObject private var model: AISummaryEditorModel
    @State private var confirmation: AISummaryConfirmation?
    @State private var privacyRuleRoute: AIClassificationPrivacyRuleRoute?
    @State private var callLogRoute: AISummaryCallLogRoute?
    @FocusState private var isEditorFocused: Bool

    init(
        repoPath: String,
        fileID: Int64,
        privacyContext: AISummaryPrivacyContext = AISummaryPrivacyContext()
    ) {
        self.repoPath = repoPath; self.fileID = fileID; self.privacyContext = privacyContext
        _model = StateObject(wrappedValue: AISummaryEditorModel(
            repoPath: repoPath,
            fileID: fileID,
            privacyContext: privacyContext
        ))
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
            Button(confirmation?.actionTitle ?? "", role: confirmation?.isDestructive == true ? .destructive : nil) {
                performConfirmedAction()
            }
        } message: {
            Text(confirmation?.message ?? "")
        }
        .sheet(item: $privacyRuleRoute) { route in
            AIClassificationPrivacyRuleReferenceSheet(repoPath: repoPath, ruleID: route.ruleID) {
                privacyRuleRoute = nil
            }
        }
        .sheet(item: $callLogRoute) { route in
            AIClassificationCallLogDetailSheet(
                repoPath: repoPath,
                callLogID: route.callLogID,
                feature: .summary
            ) {
                callLogRoute = nil
            }
        }
        .onChange(of: AISummaryEditorIdentity(fileID: fileID, privacyContext: privacyContext)) { _, identity in
            model.reset(fileID: identity.fileID)
            model.updatePrivacyContext(identity.privacyContext)
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
                Text(provenanceTitle(provenance))
                Text("Model: \(provenance.modelName ?? "Not recorded")")
                Text("Used fields: \(summaryUsedFields(provenance.usedContext))")
                if let generatedAt = provenance.generatedAt {
                    Text("Generated: \(generatedAt)")
                }
                if let privacySkip = model.privacySkip {
                    Text(privacySkip.reasonLabel)
                    Text(privacySkip.message)
                    Text("Sent fields: \(privacySentFields(privacySkip.sentFields))")
                    if let ruleID = privacySkip.ruleID {
                        Button("View privacy rule") {
                            privacyRuleRoute = AIClassificationPrivacyRuleRoute(ruleID: ruleID)
                        }
                            .accessibilityIdentifier("S3-06-C3-09-view-privacy-rule-\(ruleID)")
                    }
                    if let callLogID = provenance.callLogID {
                        Button("View AI call") {
                            callLogRoute = AISummaryCallLogRoute(callLogID: callLogID)
                        }
                        .buttonStyle(.link)
                        .accessibilityIdentifier("S3-06-C3-09-view-ai-call-\(callLogID)")
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier(model.privacySkip == nil ? "S3-06-C3-06-provenance" : "S3-06-C3-09-privacy-skip")
        }
    }

    private func provenanceTitle(_ provenance: AISummaryProvenance) -> String {
        if model.privacySkip == nil {
            return provenance.route.map(aiSummaryRouteLabel) ?? "Draft"
        }
        return model.status.label
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

    private var saveTitle: String { model.operation == .saving ? "Saving summary..." : "Save" }

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
