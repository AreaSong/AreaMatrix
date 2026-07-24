import SwiftUI

struct AISummaryEditor: View {
    @EnvironmentObject private var localizer: AppLocalizer
    private let repoPath: String
    private let fileID: Int64
    private let privacyContext: AISummaryPrivacyContext
    private let exitController: AISummaryEditorExitController?
    private let onOpenAISettings: () -> Void
    private let onBackToDetail: () -> Void
    @StateObject private var model: AISummaryEditorModel
    @State private var confirmation: AISummaryConfirmation?
    @State private var privacyRuleRoute: AIPrivacyRulesRoute?
    @State private var callLogRoute: AISummaryCallLogRoute?
    @FocusState private var isEditorFocused: Bool
    init(
        repoPath: String,
        fileID: Int64,
        privacyContext: AISummaryPrivacyContext = AISummaryPrivacyContext(),
        exitController: AISummaryEditorExitController? = nil,
        onOpenAISettings: @escaping () -> Void = {},
        onBackToDetail: @escaping () -> Void = {}
    ) {
        self.repoPath = repoPath; self.fileID = fileID; self.privacyContext = privacyContext
        self.exitController = exitController
        self.onOpenAISettings = onOpenAISettings
        self.onBackToDetail = onBackToDetail
        _model = StateObject(wrappedValue: AISummaryEditorModel(
            repoPath: repoPath,
            fileID: fileID,
            privacyContext: privacyContext
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            gateNoticeView
            provenanceRows
            clearConflictNoticeView
            saveConflictReviewView
            replacementReviewView
            editor
            progressView
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
            AIPrivacyRulesRouteSheet(repoPath: repoPath, focus: route.focus, onClose: {
                privacyRuleRoute = nil
            })
        }
        .sheet(item: $callLogRoute) { route in
            AIClassificationCallLogDetailSheet(
                repoPath: repoPath,
                callLogID: route.callLogID,
                feature: .summary,
                onClose: {
                    callLogRoute = nil
                }
            )
        }
        .onChange(of: AISummaryEditorIdentity(fileID: fileID, privacyContext: privacyContext)) { _, identity in
            model.reset(fileID: identity.fileID)
            model.updatePrivacyContext(identity.privacyContext)
            syncExitController()
        }
        .task(id: AISummaryEditorIdentity(fileID: fileID, privacyContext: privacyContext)) {
            await model.loadEntryState()
        }
        .onAppear(perform: syncExitController)
        .onChange(of: model.status) { _, _ in syncExitController() }
        .onChange(of: model.operation) { _, _ in syncExitController() }
        .onChange(of: model.draftText) { _, _ in syncExitController() }
        .accessibilityIdentifier("ai-summary-ai-summary-core-ai-summary-editor")
    }
}

private extension AISummaryEditor {
    private var header: some View {
        HStack {
            Text("AI Summary").font(.headline).accessibilityAddTraits(.isHeader)
            Text(model.status.label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            Text(model.characterCountText).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var gateNoticeView: some View {
        switch model.gateState {
        case .unknown:
            EmptyView()
        case .checking:
            Label("Checking AI summary gate...", systemImage: "arrow.triangle.2.circlepath")
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("ai-summary-ai-summary-core-generate-gate-checking")
        case .allowed:
            EmptyView()
        case let .blocked(notice):
            AISummaryGateNoticeView(
                notice: notice,
                repoPath: repoPath,
                accessibilityID: gateAccessibilityID(for: notice),
                onOpenAISettings: onOpenAISettings,
                onOpenPrivacyRule: { privacyRuleRoute = $0 }
            )
        case let .failed(error):
            VStack(alignment: .leading, spacing: 4) {
                Label(localizer.resolve(error.message), systemImage: "exclamationmark.triangle")
                Text(error.detail).font(.caption)
                Text(localizer.resolve(error.recovery)).font(.caption)
            }
            .foregroundStyle(.orange)
            .accessibilityIdentifier("ai-summary-ai-summary-core-generate-gate-error")
        }
    }

    private func gateAccessibilityID(for notice: AISummaryEditorNotice) -> String {
        notice.capability == "ai-privacy-rules-core" ?
            "ai-summary-ai-privacy-rules-core-privacy-gate" :
            "ai-summary-ai-summary-core-generate-gate"
    }

    @ViewBuilder
    private var provenanceRows: some View {
        if let provenance = model.provenance {
            VStack(alignment: .leading, spacing: 4) {
                Text(provenanceTitle(provenance))
                Text(summaryOwnershipLabel(provenance.ownership))
                if let locale = provenance.contentLocale {
                    Text(L10n.format("ai.summary.contentLanguage", summaryLocaleLabel(locale)))
                }
                Text(L10n.format("ai.summary.model", provenance.modelName ?? L10n.string("Not recorded")))
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
                            privacyRuleRoute = AIPrivacyRulesRoute(repoPath: repoPath, focus: .rule(ruleID: ruleID))
                        }
                        .accessibilityIdentifier("ai-summary-ai-privacy-rules-core-view-privacy-rule-\(ruleID)")
                    } else if let field = privacySkip.matchedField {
                        Button("View privacy rule") {
                            privacyRuleRoute = AIPrivacyRulesRoute(repoPath: repoPath, focus: .field(field))
                        }
                        .accessibilityIdentifier("ai-summary-ai-privacy-rules-core-view-privacy-field-\(field)")
                    }
                }
                if let callLogID = provenance.callLogID {
                    Button("View AI call") {
                        callLogRoute = AISummaryCallLogRoute(callLogID: callLogID)
                    }
                    .buttonStyle(.link)
                    .accessibilityIdentifier("ai-summary-\(callLogCapability)-view-ai-call-\(callLogID)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier(
                model.privacySkip == nil ?
                    "ai-summary-ai-summary-core-provenance" :
                    "ai-summary-ai-privacy-rules-core-privacy-skip"
            )
        }
    }

    private func provenanceTitle(_ provenance: AISummaryProvenance) -> String {
        if model.privacySkip == nil {
            return provenance.route.map(aiSummaryRouteLabel) ?? L10n.string("Draft")
        }
        return model.status.label
    }

    private var callLogCapability: String {
        model.privacySkip == nil ? "ai-summary-core" : "ai-privacy-rules-core"
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
            .accessibilityLabel(L10n.string("AI summary draft"))
    }

    @ViewBuilder
    private var clearConflictNoticeView: some View {
        if let notice = model.clearConflictNotice {
            VStack(alignment: .leading, spacing: 6) {
                Label("The summary changed before it could be cleared", systemImage: "arrow.clockwise")
                    .font(.headline)
                Text(L10n.format(
                    "ai.summary.clearConflict.revisions",
                    notice.expectedRevision,
                    notice.currentRevision
                ))
                Text("The latest summary has been loaded. Review it and choose Clear summary again if needed.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(10)
            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier("ai-summary-clear-content-revision-conflict")
        }
    }

    @ViewBuilder
    private var saveConflictReviewView: some View {
        if let review = model.saveConflictReview {
            VStack(alignment: .leading, spacing: 10) {
                Label("Summary changed in another window", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                Text(L10n.format(
                    "ai.summary.conflict.revisions",
                    review.expectedRevision,
                    review.currentRevision
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 12) {
                    conflictSummaryColumn(
                        title: L10n.string("Latest saved summary"),
                        text: review.latestState.summary?.summaryText ?? L10n.string("No saved summary")
                    )
                    conflictSummaryColumn(
                        title: L10n.string("Your local draft"),
                        text: review.localText
                    )
                }
                Text("Reviewing updates the baseline only. You must Save again to apply your draft.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Reload latest", action: model.reloadLatestAfterSaveConflict)
                    Spacer()
                    Button("Review changes", action: model.reviewLatestAfterSaveConflict)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(10)
            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier("ai-summary-content-revision-conflict-review")
        }
    }

    private func conflictSummaryColumn(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold))
            Text(text).frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
    }

    @ViewBuilder
    private var replacementReviewView: some View {
        if let review = model.replacementReview {
            VStack(alignment: .leading, spacing: 10) {
                Text("Review summary replacement")
                    .font(.headline)
                Text("The saved user-owned summary will remain unchanged until you explicitly replace it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 12) {
                    summaryReplacementColumn(
                        title: L10n.string("Current saved summary"),
                        text: review.savedText,
                        provenance: review.savedProvenance
                    )
                    summaryReplacementColumn(
                        title: L10n.string("New summary draft"),
                        text: review.candidateText,
                        provenance: review.candidateProvenance
                    )
                }
                HStack {
                    Button("Keep existing", action: model.keepExistingSummary)
                    Button("Continue editing", action: model.continueEditingReplacement)
                    Spacer()
                    Button("Replace") { Task { await model.replaceReviewedSummary() } }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier("ai-summary-user-owned-replacement-review")
        }
    }

    private func summaryReplacementColumn(
        title: String,
        text: String,
        provenance: AISummaryProvenance
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold))
            Text(text).frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
            Text(summaryOwnershipLabel(provenance.ownership))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
    }
}

private extension AISummaryEditor {
    @ViewBuilder
    private var progressView: some View {
        if let progressText = model.operation.progressText {
            Label(progressText, systemImage: "arrow.triangle.2.circlepath")
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("ai-summary-ai-summary-core-operation-progress")
        }
    }

    @ViewBuilder
    private var errorView: some View {
        if case let .failed(error) = model.operation {
            VStack(alignment: .leading, spacing: 8) {
                Label(localizer.resolve(error.message), systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                Text(error.detail).font(.caption).foregroundStyle(.secondary)
                Text(localizer.resolve(error.recovery)).font(.caption).foregroundStyle(.secondary)
                failedActionControls
            }
            .accessibilityIdentifier("ai-summary-ai-summary-core-error")
        }
    }

    @ViewBuilder
    private var failedActionControls: some View {
        switch model.failedAction {
        case .load:
            HStack {
                Button("Retry load") { Task { await model.loadEntryState() } }
                Button("Back to detail", action: onBackToDetail)
            }
        case .generate:
            HStack {
                Button("Retry generate") { Task { await model.retryGeneration() } }
                Button("Cancel", action: model.cancelFailedAction)
            }
        case .save:
            HStack {
                Button("Retry save") { Task { await model.save() } }
                Button("Discard changes", action: model.discardChanges)
                Button("Back to detail", action: onBackToDetail)
            }
        case .clear:
            HStack {
                Button("Retry clear") { Task { await model.clear() } }
                Button("Cancel", action: model.cancelFailedAction)
            }
        case nil:
            EmptyView()
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
        model.operation == .saving ? L10n.string("Saving summary...") : L10n.string("Save")
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

    private func syncExitController() {
        exitController?.update(needsConfirmation: model.needsExitConfirmation) {
            await model.save()
        } discardHandler: {
            model.discardChanges()
        }
    }

    private func summaryOwnershipLabel(_ ownership: AiContentOwnership) -> String {
        ownership == .userOwned ? L10n.string("User-owned") : L10n.string("Generated")
    }

    private func summaryLocaleLabel(_ locale: ContentLocale) -> String {
        locale == .zhHans ? L10n.string("简体中文") : L10n.string("English")
    }
}
