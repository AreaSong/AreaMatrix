import Combine
import Foundation
import SwiftUI

enum AIPrivacyRemoteProviderLoadState: Equatable {
    case loading, loaded, failed(AISettingsError)
}

enum AIPrivacyRulesLoadState: Equatable {
    case loading, loaded, failed(AISettingsError)
}

@MainActor
final class AIPrivacyRemoteProviderStateModel: ObservableObject {
    @Published private(set) var loadState: AIPrivacyRemoteProviderLoadState = .loading
    @Published private(set) var snapshot: RemoteProviderConfigState?

    let repoPath: String
    private let providerReader: any CoreRemoteProviderConfiguring
    private let errorMapper: any CoreErrorMapping

    init(
        repoPath: String,
        providerReader: any CoreRemoteProviderConfiguring = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge()
    ) {
        self.repoPath = repoPath
        self.providerReader = providerReader
        self.errorMapper = errorMapper
    }

    var allowsPrivacyGateEnable: Bool {
        guard let snapshot else { return false }
        return snapshot.providerConfigured && snapshot.providerVerified &&
            snapshot.remoteProviderEnabled && !snapshot.featureScope.isEmpty
    }

    var providerStatusText: String {
        switch loadState {
        case .loading: "Loading remote provider..."
        case .failed: "Remote provider state unavailable"
        case .loaded: loadedProviderStatusText
        }
    }

    var verifiedStatusText: String {
        guard let snapshot else { return "Loading" }
        return snapshot.providerVerified ? "Connection tested" : "Connection test required"
    }

    var enabledStatusText: String {
        guard let snapshot else { return "Loading" }
        return snapshot.remoteProviderEnabled ? "Remote provider enabled" : "Remote provider disabled"
    }

    var featureScopeText: String {
        guard let snapshot else { return "Loading" }
        guard !snapshot.featureScope.isEmpty else { return "No remote usage scope selected" }
        return snapshot.featureScope.map(\.title).joined(separator: ", ")
    }

    func load() async {
        loadState = .loading
        do {
            snapshot = try await providerReader.loadRemoteProviderConfig(repoPath: repoPath)
            loadState = .loaded
        } catch {
            snapshot = nil
            loadState = await .failed(providerError(for: error))
        }
    }

    private var loadedProviderStatusText: String {
        guard let snapshot else { return "Remote provider state unavailable" }
        if !snapshot.providerConfigured { return "Configure remote AI required" }
        if !snapshot.providerVerified { return "Remote provider needs connection test." }
        if !snapshot.remoteProviderEnabled { return "Remote provider is disabled in AI settings." }
        if snapshot.featureScope.isEmpty { return "Remote scope is not selected." }
        return "Configured by S3-03"
    }

    private func providerError(for error: Error) async -> AISettingsError {
        if let coreError = error as? CoreError {
            let mapping = await errorMapper.mapCoreError(coreError)
            return AISettingsError(
                message: "Remote provider state could not be loaded.",
                recovery: mapping.suggestedAction.isEmpty ? "Retry or configure remote AI." : mapping.suggestedAction,
                detail: mapping.userMessage
            )
        }
        return AISettingsError(
            message: "Remote provider state could not be loaded.",
            recovery: "Retry or configure remote AI.",
            detail: error.localizedDescription
        )
    }
}

struct AIPrivacyRulesView: View {
    @ObservedObject var model: AISettingsModel
    @StateObject private var providerModel: AIPrivacyRemoteProviderStateModel
    @StateObject private var privacyModel: AIPrivacyRulesModel
    @State private var draftKind = AiPrivacyRuleKind.folder
    @State private var draftPattern = ""
    @State private var draftAppliesTo = AiPrivacyRuleAppliesTo.remoteAi
    @State private var testPath = "finance/private/q1.pdf"
    @State private var deletionCandidate: AiPrivacyRuleRecord?

    let onConfigureRemoteAI: () -> Void
    let onClose: () -> Void

    init(
        model: AISettingsModel,
        providerModel: AIPrivacyRemoteProviderStateModel? = nil,
        privacyModel: AIPrivacyRulesModel? = nil,
        onConfigureRemoteAI: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.model = model
        _providerModel = StateObject(wrappedValue: providerModel ??
            AIPrivacyRemoteProviderStateModel(repoPath: model.repoPath))
        _privacyModel = StateObject(wrappedValue: privacyModel ?? AIPrivacyRulesModel(repoPath: model.repoPath))
        self.onConfigureRemoteAI = onConfigureRemoteAI
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView { VStack(alignment: .leading, spacing: 18) { bodyContent }.padding(24) }
            Divider()
            footer
        }
        .frame(width: 720, height: 660)
        .task { await loadPage() }
        .alert("Delete privacy rule?", isPresented: deleteConfirmation) {
            Button("Cancel", role: .cancel) { deletionCandidate = nil }
            Button("Delete rule", role: .destructive) { confirmDeleteRule() }
        } message: {
            Text("Future AI calls may no longer skip content that matched this rule. This will not delete files.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("AI Privacy Rules").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
            Text(model.repoPath).font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
        }
        .padding(24)
    }

    @ViewBuilder
    private var bodyContent: some View {
        switch model.loadState {
        case .loading: ProgressView("Loading privacy rules...")
        case let .failed(error):
            AISettingsInlineBanner(error: error, tint: .red) { Button("Retry", action: retryLoad) }
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
        case .loading: ProgressView("Loading privacy rules...")
        case let .failed(error):
            AISettingsInlineBanner(error: error, tint: .red) { Button("Retry", action: retryPrivacyRules) }
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

    private var fieldSection: some View {
        AdvancedSettingsSection(title: "Remote allowed fields") {
            if !privacyModel.canEditRemoteFields {
                Text("Remote AI is blocked.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(privacyModel.fields, id: \.field) { field in
                Toggle(isOn: fieldBinding(field)) {
                    Text("\(aiPrivacyInputFieldLabel(field.field)) - \(field.lastMatchedCount) recent matches")
                }
                .disabled(!privacyModel.canEditRemoteFields)
            }
        }
    }

    private var ruleListSection: some View {
        AdvancedSettingsSection(title: "Privacy rules") {
            if privacyModel.rules.isEmpty { Text("No AI privacy rules yet. Remote AI is still off by default.") }
            ForEach(privacyModel.rules, id: \.ruleId) { rule in
                HStack {
                    Text(rule.enabled ? "Enabled" : "Disabled").frame(width: 70, alignment: .leading)
                    Text("\(rule.kind.s309Label): \(rule.pattern)")
                    Spacer()
                    Text("\(rule.appliesTo.s309Label), \(rule.matchCount) files").foregroundStyle(.secondary)
                    Button(rule.enabled ? "Disable" : "Enable") { toggleRule(rule) }
                    Button("Delete...") { deletionCandidate = rule }
                }
                .font(.callout)
            }
        }
    }

    private var ruleEditorSection: some View {
        AdvancedSettingsSection(title: "Add rule") {
            Picker("Type", selection: $draftKind) {
                ForEach(AiPrivacyRuleKind.s309Cases, id: \.self) { Text($0.s309Label).tag($0) }
            }
            TextField("Pattern", text: $draftPattern).textFieldStyle(.roundedBorder)
            Picker("Applies to", selection: $draftAppliesTo) {
                Text("Remote AI").tag(AiPrivacyRuleAppliesTo.remoteAi)
                Text("Local and remote AI").tag(AiPrivacyRuleAppliesTo.localAndRemoteAi)
            }
            .pickerStyle(.segmented)
            HStack {
                Button("Save rule", action: saveDraftRule)
                    .disabled(!draftIsValid || privacyModel.isSaving)
                    .accessibilityIdentifier("S3-09-C3-09-save-rule")
                Text(draftValidationMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var testRulesSection: some View {
        AdvancedSettingsSection(title: "Test rules") {
            TextField("Test repo-relative path", text: $testPath).textFieldStyle(.roundedBorder)
            Button("Test rules", action: testRules)
                .disabled(privacyModel.isEvaluating || testPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("S3-09-C3-09-test-rules")
            if let report = privacyModel.evaluation {
                Text("\(report.decision.s309Label): \(report.message)")
                Text("Sent fields: \(privacySentFields(report.sentFields))")
                    .font(.caption).foregroundStyle(.secondary)
                if !report.matchedRules.isEmpty {
                    Text("Matched by \(report.matchedRules.map(\.name).joined(separator: ", "))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var feedbackBanner: some View {
        if let error = privacyModel.saveError {
            AISettingsInlineBanner(error: error, tint: .red) { Button("Retry", action: retryPrivacyRules) }
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
            Button("Close", action: onClose)
        }
        .padding(16)
    }

    private var remoteGateStatus: String {
        privacyModel.snapshot?.privacyGateEnabled == true ? "Remote AI allowed" : "Remote AI blocked"
    }

    private var allowRemoteGateDisabled: Bool {
        privacyModel.isSaving || !providerModel.allowsPrivacyGateEnable
    }

    private var draftIsValid: Bool {
        !draftPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !draftPattern.hasPrefix("/")
    }

    private var draftValidationMessage: String {
        if draftPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Pattern is required." }
        if draftPattern.hasPrefix("/") { return "Use a path relative to the AreaMatrix repository root." }
        return "Ready to save."
    }

    private var deleteConfirmation: Binding<Bool> {
        Binding(get: { deletionCandidate != nil }, set: { if !$0 { deletionCandidate = nil } })
    }

    private func fieldBinding(_ field: AiPrivacyFieldState) -> Binding<Bool> {
        Binding(
            get: { field.allowRemote },
            set: { allow in Task { await privacyModel.setField(field.field, allowRemote: allow) } }
        )
    }

    private func loadPage() async {
        if !model.isLoaded { await model.load() }
        await providerModel.load()
        await privacyModel.load()
    }

    private func retryLoad() {
        Task { await loadPage() }
    }

    private func retryProviderLoad() {
        Task { await providerModel.load() }
    }

    private func retryPrivacyRules() {
        Task { await privacyModel.load() }
    }

    private func allowRemoteGate() {
        Task { await privacyModel.setPrivacyGate(true) }
    }

    private func blockRemoteGate() {
        Task { await privacyModel.setPrivacyGate(false) }
    }

    private func toggleRule(_ rule: AiPrivacyRuleRecord) {
        Task { await privacyModel.setRuleEnabled(rule, enabled: !rule.enabled) }
    }

    private func saveDraftRule() {
        Task {
            let didSave = await privacyModel.addRule(kind: draftKind, pattern: draftPattern, appliesTo: draftAppliesTo)
            if didSave { draftPattern = "" }
        }
    }

    private func testRules() {
        Task { await privacyModel.evaluate(repoRelativePath: testPath) }
    }

    private func confirmDeleteRule() {
        guard let deletionCandidate else { return }
        self.deletionCandidate = nil
        Task { await privacyModel.deleteRule(deletionCandidate) }
    }
}

extension AiPrivacyRuleInput {
    init(s309Record record: AiPrivacyRuleRecord) {
        self.init(
            ruleId: record.ruleId,
            name: record.name,
            kind: record.kind,
            pattern: record.pattern,
            appliesTo: record.appliesTo,
            enabled: record.enabled,
            description: record.description
        )
    }
}

extension AiPrivacyRulesSnapshot {
    var ruleInputs: [AiPrivacyRuleInput] {
        rules.map(AiPrivacyRuleInput.init(s309Record:))
    }

    var fieldRules: [AiPrivacyFieldRule] {
        remoteAllowedFields.map(AiPrivacyFieldRule.init(state:))
    }

    func s309EvaluationRequest(repoRelativePath: String) -> AiPrivacyEvaluationRequest {
        AiPrivacyEvaluationRequest(
            feature: .autoSummaries,
            route: .remote,
            requestedFields: remoteAllowedFields.map(\.field),
            privacyGateEnabled: privacyGateEnabled,
            providerScope: providerScope,
            rules: ruleInputs,
            remoteAllowedFields: fieldRules,
            context: AiPrivacyEvaluationContext(
                fileId: nil,
                repoRelativePath: repoRelativePath,
                fileName: (repoRelativePath as NSString).lastPathComponent,
                category: nil,
                extension: (repoRelativePath as NSString).pathExtension,
                tags: []
            )
        )
    }
}

extension AiPrivacyRuleKind {
    static let s309Cases: [AiPrivacyRuleKind] = [.folder, .category, .keyword, .extension, .tag]
    var s309Label: String {
        switch self {
        case .folder: "Folder"
        case .category: "Category"
        case .keyword: "Keyword"
        case .extension: "Extension"
        case .tag: "Tag"
        }
    }
}

extension AiPrivacyRuleAppliesTo {
    var s309Label: String {
        switch self {
        case .remoteAi: "Remote AI"
        case .localAndRemoteAi: "Local and remote AI"
        }
    }
}

private extension AiPrivacyDecision {
    var s309Label: String {
        switch self {
        case .allowed: "Allowed"
        case .denied: "Denied"
        case .skipped: "Skipped"
        }
    }
}
