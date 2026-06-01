import Combine
import Foundation
import SwiftUI

struct AIPrivacyRulesView: View {
    @ObservedObject var model: AISettingsModel
    @StateObject var providerModel: AIPrivacyRemoteProviderStateModel
    @StateObject var privacyModel: AIPrivacyRulesModel
    @State var editorMode = AIPrivacyRuleEditorMode.hidden
    @State var editorDraft = AIPrivacyRuleEditorDraft()
    @State var pendingExitAction: AIPrivacyRuleExitAction?
    @State private var isTemplateSheetPresented = false
    @State private var selectedTemplates: Set<AIPrivacyRuleTemplate> = []
    @State var testFileContext = AIPrivacyRuleTestFileContext(repoRelativePath: "", category: nil, tags: [])
    @State var deletionCandidate: AiPrivacyRuleRecord?
    @State private var pendingFocus: AIPrivacyRulesRouteFocus?
    @State private var consumedFocus: AIPrivacyRulesRouteFocus?

    let registry: AIPrivacyRuleRegistrySnapshot
    let initialFocus: AIPrivacyRulesRouteFocus?
    let onConfigureRemoteAI: () -> Void
    let onClose: () -> Void

    init(
        model: AISettingsModel,
        providerModel: AIPrivacyRemoteProviderStateModel? = nil,
        privacyModel: AIPrivacyRulesModel? = nil,
        registry: AIPrivacyRuleRegistrySnapshot = .unavailable,
        initialFocus: AIPrivacyRulesRouteFocus? = nil,
        onConfigureRemoteAI: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.model = model
        _providerModel = StateObject(wrappedValue: providerModel ??
            AIPrivacyRemoteProviderStateModel(repoPath: model.repoPath))
        _privacyModel = StateObject(wrappedValue: privacyModel ??
            AIPrivacyRulesModel(repoPath: model.repoPath, settingsSync: model))
        self.registry = registry
        self.initialFocus = initialFocus
        self.onConfigureRemoteAI = onConfigureRemoteAI
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                ScrollView { VStack(alignment: .leading, spacing: 18) { bodyContent }.padding(24) }
                    .onChange(of: pendingFocus) { _, focus in scrollToFocus(focus, proxy: proxy) }
            }
            Divider()
            footer
        }
        .frame(width: 760, height: 700)
        .task { await loadPage() }
        .sheet(isPresented: $isTemplateSheetPresented) {
            AIPrivacyRuleTemplatesSheet(
                selectedTemplates: $selectedTemplates,
                isSaving: privacyModel.isSaving,
                onCancel: closeTemplates,
                onAdd: addSelectedTemplates
            )
        }
        .alert("Delete privacy rule?", isPresented: deleteConfirmation) {
            Button("Cancel", role: .cancel) { deletionCandidate = nil }
            Button("Delete rule", role: .destructive) { confirmDeleteRule() }
        } message: {
            Text(
                "Future AI calls may no longer skip content that matched this rule. " +
                    "This will not delete files, existing AI results, tags, summaries, notes, or call logs."
            )
        }
        .confirmationDialog(
            "You have unsaved changes.",
            isPresented: unsavedExitConfirmation,
            titleVisibility: .visible
        ) {
            Button("Cancel", role: .cancel) { pendingExitAction = nil }
            Button("Discard changes", role: .destructive, action: discardPendingExit)
            Button("Save changes") { Task { await saveDraftAndContinuePendingExit() } }
                .disabled(!editorDraft.canSave(registry: registry) || privacyModel.isSaving)
        } message: {
            Text("Save or discard the privacy rule edit before leaving.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI Privacy Rules").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
            Text(model.repoPath).font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            Text(
                "Privacy rules are checked before AI uses file metadata or extracted text. " +
                    "Remote AI is blocked by default for matching rules."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(24)
    }

    @ViewBuilder
    private var bodyContent: some View {
        switch model.loadState {
        case .loading:
            ProgressView("Loading privacy rules...")
        case let .failed(error):
            AISettingsInlineBanner(error: error, tint: .red) {
                Button("Retry", action: retryLoad)
                Button("Back to AI settings", action: requestClose)
            }
        case .loaded:
            loadedContent
        }
    }

    private var loadedContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            feedbackBanner
            providerLoadFailureBanner
            remoteGateSection
            privacyRulesContent
        }
    }

    private var remoteGateSection: some View {
        AdvancedSettingsSection(title: "Remote AI privacy gate") {
            AdvancedSettingsKeyValueRow(label: "Status", value: remoteGateStatus)
            AdvancedSettingsKeyValueRow(label: "Remote provider", value: providerModel.providerStatusText)
            AdvancedSettingsKeyValueRow(label: "Provider verified", value: providerModel.verifiedStatusText)
            AdvancedSettingsKeyValueRow(label: "Remote provider enabled", value: providerModel.enabledStatusText)
            AdvancedSettingsKeyValueRow(label: "Feature scope", value: providerModel.featureScopeText)
            Text(
                "This is a privacy gate, not the provider disable page. Blocking here does not delete " +
                    "Keychain credentials, provider configuration, local AI settings, summaries, tags, or call logs."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("Allow remote AI after provider consent", action: allowRemoteGate)
                    .disabled(allowRemoteGateDisabled)
                    .accessibilityIdentifier("S3-09-C3-09-allow-remote-ai-after-provider-consent")
                Button("Block remote AI with privacy gate", action: blockRemoteGate)
                    .disabled(privacyModel.isSaving || privacyModel.snapshot?.privacyGateEnabled == false)
                    .accessibilityIdentifier("S3-09-C3-09-block-remote-ai-privacy-gate")
            }
            Button("Configure remote AI", action: onConfigureRemoteAI)
                .accessibilityIdentifier("S3-09-C3-03-configure-remote-ai")
        }
    }

    @ViewBuilder
    private var privacyRulesContent: some View {
        switch privacyModel.loadState {
        case .loading:
            ProgressView("Loading privacy rules...")
        case let .failed(error):
            AISettingsInlineBanner(error: error, tint: .red) {
                Button("Retry", action: retryPrivacyRules)
                Button("Back to AI settings", action: requestClose)
            }
        case .loaded:
            privacyRulesLoadedContent
        }
    }

    private var privacyRulesLoadedContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            fieldSection
            ruleListSection
            ruleEditorSection
            testRulesSection
        }
    }

    @ViewBuilder
    private var feedbackBanner: some View {
        if let error = privacyModel.saveError {
            AISettingsInlineBanner(error: error, tint: .red) {
                Button("Retry save") { Task { await privacyModel.retrySave() } }
                Button("Revert changes", action: privacyModel.revertPendingSave)
            }
        } else if let feedback = privacyModel.feedback {
            Label(feedback, systemImage: "checkmark.circle").foregroundStyle(.green)
        }
    }

    @ViewBuilder
    private var providerLoadFailureBanner: some View {
        if case let .failed(error) = providerModel.loadState {
            AISettingsInlineBanner(error: error, tint: .red) {
                Button("Retry", action: retryProviderLoad)
                Button("Configure remote AI", action: onConfigureRemoteAI)
            }
        }
    }

    private var footer: some View {
        HStack {
            if privacyModel.isSaving {
                ProgressView().controlSize(.small).accessibilityLabel("Saving AI privacy rules")
            }
            Spacer()
            Button("Close", action: requestClose)
        }
        .padding(16)
    }

    private var remoteGateStatus: String {
        privacyModel.snapshot?.privacyGateEnabled == true ? "Remote AI allowed" : "Remote AI blocked"
    }

    private var allowRemoteGateDisabled: Bool {
        privacyModel.isSaving || !providerModel.allowsPrivacyGateEnable
    }

    private var deleteConfirmation: Binding<Bool> {
        Binding(get: { deletionCandidate != nil }, set: { if !$0 { deletionCandidate = nil } })
    }

    private var unsavedExitConfirmation: Binding<Bool> {
        Binding(get: { pendingExitAction != nil }, set: { if !$0 { pendingExitAction = nil } })
    }

    var testPath: Binding<String> {
        Binding(get: { testFileContext.repoRelativePath }, set: { testFileContext.repoRelativePath = $0 })
    }

    var testCategoryBinding: Binding<String> {
        Binding(
            get: { testFileContext.category ?? "" },
            set: { testFileContext.category = cleanOptionalText($0) }
        )
    }

    var testTagsBinding: Binding<String> {
        Binding(
            get: { testFileContext.tags.joined(separator: ", ") },
            set: { value in
                testFileContext.tags = value
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    func fieldBinding(_ field: AiPrivacyFieldState) -> Binding<Bool> {
        Binding(
            get: { field.allowRemote },
            set: { allow in Task { await privacyModel.setField(field.field, allowRemote: allow) } }
        )
    }

    private func loadPage() async {
        if !model.isLoaded { await model.load() }
        await providerModel.load()
        await privacyModel.load()
        applyInitialFocusIfNeeded()
    }

    private func retryLoad() { Task { await loadPage() } }

    private func retryProviderLoad() { Task { await providerModel.load() } }

    private func retryPrivacyRules() { Task { await privacyModel.load() } }

    private func allowRemoteGate() {
        guard providerModel.allowsPrivacyGateEnable else {
            onConfigureRemoteAI()
            return
        }
        Task { await privacyModel.setPrivacyGate(true) }
    }

    private func blockRemoteGate() {
        Task { await privacyModel.setPrivacyGate(false) }
    }

    func toggleRule(_ rule: AiPrivacyRuleRecord) {
        Task { await privacyModel.setRuleEnabled(rule, enabled: !rule.enabled) }
    }

    func beginAddRule() {
        transitionFromDirtyEditor(or: .openAddEditor) {
            editorDraft = AIPrivacyRuleEditorDraft()
            editorMode = .visible
        }
    }

    func beginEditRule(_ rule: AiPrivacyRuleRecord) {
        transitionFromDirtyEditor(or: .switchRule(rule)) {
            editorDraft = AIPrivacyRuleEditorDraft(record: rule)
            editorMode = .visible
        }
    }

    func cancelEditor() {
        transitionFromDirtyEditor(or: .cancelEditor) {
            editorDraft = AIPrivacyRuleEditorDraft()
            editorMode = .hidden
        }
    }

    func saveDraftRule() {
        Task {
            let didSave = await privacyModel.saveRule(editorDraft.input)
            if didSave {
                editorDraft = AIPrivacyRuleEditorDraft()
                editorMode = .hidden
            }
        }
    }

    func testRules() {
        Task { await privacyModel.evaluate(context: testFileContext) }
    }

    private func confirmDeleteRule() {
        guard let deletionCandidate else { return }
        self.deletionCandidate = nil
        Task { await privacyModel.deleteRule(deletionCandidate) }
    }

    private func requestClose() {
        transitionFromDirtyEditor(or: .close, action: onClose)
    }

    func openTemplates() {
        selectedTemplates = []
        isTemplateSheetPresented = true
    }

    private func closeTemplates() {
        selectedTemplates = []
        isTemplateSheetPresented = false
    }

    private func addSelectedTemplates() {
        Task {
            let inputs = AIPrivacyRuleTemplate.allCases
                .filter { selectedTemplates.contains($0) }
                .map(\.ruleInput)
            let didAdd = await privacyModel.addRules(inputs)
            if didAdd { closeTemplates() }
        }
    }

    private func transitionFromDirtyEditor(or pending: AIPrivacyRuleExitAction, action: () -> Void) {
        guard editorMode == .visible, editorDraft.hasChanges else {
            action()
            return
        }
        pendingExitAction = pending
    }

    private func discardPendingExit() {
        guard let action = pendingExitAction else { return }
        pendingExitAction = nil
        editorDraft = AIPrivacyRuleEditorDraft()
        editorMode = .hidden
        performExitAction(action)
    }

    private func saveDraftAndContinuePendingExit() async {
        guard let action = pendingExitAction else { return }
        let didSave = await privacyModel.saveRule(editorDraft.input)
        guard didSave else { return }
        pendingExitAction = nil
        editorDraft = AIPrivacyRuleEditorDraft()
        editorMode = .hidden
        performExitAction(action)
    }

    private func performExitAction(_ action: AIPrivacyRuleExitAction) {
        switch action {
        case .close:
            onClose()
        case .cancelEditor:
            break
        case .openAddEditor:
            editorDraft = AIPrivacyRuleEditorDraft()
            editorMode = .visible
        case let .switchRule(rule):
            editorDraft = AIPrivacyRuleEditorDraft(record: rule)
            editorMode = .visible
        }
    }

    private func cleanOptionalText(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func isFocused(ruleID: String) -> Bool {
        pendingFocus?.matches(ruleID: ruleID) == true
    }

    func isFocused(field: AiPrivacyInputField) -> Bool {
        pendingFocus?.matches(field: field) == true
    }

    private func applyInitialFocusIfNeeded() {
        guard consumedFocus != initialFocus else { return }
        consumedFocus = initialFocus
        pendingFocus = initialFocus
    }

    private func scrollToFocus(_ focus: AIPrivacyRulesRouteFocus?, proxy: ScrollViewProxy) {
        guard let focus else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(focus.targetID, anchor: .center)
        }
    }
}
