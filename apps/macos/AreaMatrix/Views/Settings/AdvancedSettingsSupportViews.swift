import SwiftUI

struct AdvancedSettingsRecoveryToolsSection: View {
    let onOpenRecoveryTools: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recovery tools")
                .font(.headline)
            Button {
                onOpenRecoveryTools()
            } label: {
                Label("Open recovery tools...", systemImage: "arrow.clockwise.circle")
            }
            .accessibilityIdentifier("S1-30-C1-16-open-recovery-tools")
            Text(
                "Startup cleanup and staging recovery stay in the dedicated recovery flow " +
                    "with confirmation before metadata actions."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AdvancedSettingsKeyValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
                .accessibilityLabel("\(label): \(value)")
        }
        .font(.callout)
    }
}

struct AdvancedSettingsInlineBanner: View {
    let error: AdvancedSettingsError
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error.message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(tint)
            Text(error.recovery)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

struct AdvancedSettingsSection<Content: View>: View {
    let title: String
    private let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AdvancedRootOverviewConfirmationSheet: View {
    let status: RootOverviewFileStatus
    let onCancel: () -> Void
    let onEnable: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Enable root AREAMATRIX.md?")
                .font(.title2.weight(.semibold))
            Text(
                "AreaMatrix may create or update AREAMATRIX.md at the repository root " +
                    "on the next overview regeneration. " +
                    "Existing content outside the managed marker block is preserved. README.md is never modified."
            )
            .fixedSize(horizontal: false, vertical: true)
            Text(status.confirmationDetail)
                .foregroundStyle(status.canEnableRootOverview ? Color.secondary : Color.red)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Enable root file", action: onEnable)
                    .buttonStyle(.borderedProminent)
                    .disabled(!status.canEnableRootOverview)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}

struct AISettingsInlineBanner<Actions: View>: View {
    let error: AISettingsError
    let tint: Color
    private let actions: Actions

    init(error: AISettingsError, tint: Color, @ViewBuilder actions: () -> Actions) {
        self.error = error
        self.tint = tint
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error.message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(tint)
            Text(error.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(error.recovery)
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                actions
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }
}

private struct AISettingsLoadingView: View {
    var body: some View {
        AdvancedSettingsSection(title: "AI features") {
            ProgressView("Loading AI settings...")
            Text("AI controls are disabled until C3-01 configuration is loaded.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AISettingsLoadFailureView: View {
    let error: AISettingsError
    let retry: () -> Void
    let openLog: () -> Void

    var body: some View {
        AISettingsInlineBanner(error: error, tint: .red) {
            Button("Retry", action: retry)
            Button("View AI call log", action: openLog)
        }
    }
}

private struct AISettingsFeatureRow: View {
    let row: AISettingsFeatureRowSnapshot
    var isOn: Binding<Bool>

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Toggle(row.feature.title, isOn: isOn)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 4) {
                Text(row.feature.title)
                    .font(.callout.weight(.medium))
                Text("\(row.providerLabel) - \(row.remoteScope)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let reason = row.disabledReason, !reason.isEmpty {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        [
            row.feature.title,
            row.enabled ? "on" : "off",
            row.providerLabel,
            row.remoteScope,
            row.disabledReason ?? ""
        ].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

struct AISettingsPane: View {
    @StateObject private var model: AISettingsModel
    @State private var isLocalModelStatusPresented = false

    init(repoPath: String) {
        _model = StateObject(wrappedValue: AISettingsModel(repoPath: repoPath))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    bodyContent
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, 34)
                .padding(.vertical, 28)
            }
        }
        .task {
            await model.load()
        }
        .sheet(isPresented: $isLocalModelStatusPresented) {
            LocalModelStatusView(
                model: LocalModelStatusModel(repoPath: model.repoPath),
                onClose: { isLocalModelStatusPresented = false }
            )
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("AI")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(model.repoPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
            if model.isSaving {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Saving AI settings")
            }
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 18)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        switch model.loadState {
        case .loading:
            AISettingsLoadingView()
        case let .failed(error):
            AISettingsLoadFailureView(error: error, retry: retryLoad, openLog: model.openCallLogEntry)
        case .loaded:
            loadedContent
        }
    }

    private var loadedContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            feedbackBanner
            statusSection
            providerSection
            featureSection
            privacySection
            logSection
            safetySection
        }
    }

    @ViewBuilder
    private var feedbackBanner: some View {
        if let error = model.saveError {
            AISettingsInlineBanner(error: error, tint: .red) {
                if model.hasRetryablePause {
                    Button("Retry pause", action: retryPause)
                }
                if model.hasRetryableSave {
                    Button("Retry save", action: retrySave)
                    Button("Revert changes", action: model.revertChanges)
                }
            }
        } else if let feedback = model.actionFeedback {
            switch feedback {
            case let .success(message):
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case let .failed(error):
                AISettingsInlineBanner(error: error, tint: .orange) {
                    Button("Configure remote AI", action: model.openRemoteConfigurationEntry)
                }
            }
        }
    }

    private var statusSection: some View {
        AdvancedSettingsSection(title: "AI features") {
            Toggle("Enable AI features", isOn: aiEnabledBinding)
                .disabled(writesDisabled)
            Text(statusText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var providerSection: some View {
        AdvancedSettingsSection(title: "Providers") {
            AdvancedSettingsKeyValueRow(label: "Local model", value: localModelLabel)
            AdvancedSettingsKeyValueRow(label: "Remote model", value: remoteModelLabel)
            Picker("Provider preference", selection: providerPreferenceBinding) {
                ForEach(AISettingsProviderPreference.allCases) { preference in
                    Text(preference.label).tag(preference)
                }
            }
            .pickerStyle(.segmented)
            .disabled(writesDisabled)
            .frame(maxWidth: 360)
            HStack {
                Button("Local model status", action: openLocalModelStatus)
                    .accessibilityIdentifier("S3-02-C3-02-open-local-model-status")
                Button("Configure remote AI", action: model.openRemoteConfigurationEntry)
            }
        }
    }

    private var featureSection: some View {
        AdvancedSettingsSection(title: "Feature toggles") {
            ForEach(featureRows) { row in
                AISettingsFeatureRow(row: row, isOn: featureBinding(row.feature))
                    .disabled(writesDisabled || !isFeatureEditable(row))
            }
        }
    }

    private var privacySection: some View {
        AdvancedSettingsSection(title: "Privacy") {
            AdvancedSettingsKeyValueRow(label: "Privacy rules", value: privacyRulesLabel)
            AdvancedSettingsKeyValueRow(label: "Remote AI", value: remoteScopeLabel)
            Button("Manage privacy rules", action: model.openPrivacyRulesEntry)
        }
    }

    private var logSection: some View {
        AdvancedSettingsSection(title: "Log") {
            Button("View AI call log", action: model.openCallLogEntry)
            Text("See when AI was used and whether it was local or remote.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var safetySection: some View {
        AdvancedSettingsSection(title: "Safety") {
            Button("Pause all AI", action: pauseAllAI)
                .disabled(writesDisabled || !(model.snapshot?.config.aiEnabled ?? false))
            Button("Clear AI generated suggestions...", action: model.openCallLogEntry)
                .disabled(true)
            Text("Clearing generated suggestions belongs to a later AI cleanup capability, not C3-01.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var writesDisabled: Bool {
        model.isSaving || !model.isLoaded
    }

    private var statusText: String {
        guard let config = model.snapshot?.config else {
            return "Loading AI settings..."
        }
        if !config.aiEnabled {
            return "AI is off. AreaMatrix will not call local or remote models."
        }
        if config.remoteAIAllowed {
            return "Remote AI is enabled for selected features."
        }
        return "Local AI is enabled. Files stay on this device."
    }

    private var localModelLabel: String {
        guard let config = model.snapshot?.config else { return "Loading" }
        return config.localAIEnabled ? "Ready for C3-01 route" : "Not installed"
    }

    private var remoteModelLabel: String {
        guard let config = model.snapshot?.config else { return "Loading" }
        return config.remoteAIAllowed ? "Configured by S3-03" : "Off"
    }

    private var privacyRulesLabel: String {
        guard let config = model.snapshot?.config else { return "Loading" }
        guard config.privacyGateEnabled else { return "Off" }
        return config.privacyPolicyRef ?? "Default gate enabled"
    }

    private var remoteScopeLabel: String {
        guard let config = model.snapshot?.config else { return "Loading" }
        return config.remoteAIAllowed ? "Allowed for selected features" : "Remote AI is not configured"
    }

    private var featureRows: [AISettingsFeatureRowSnapshot] {
        guard let snapshot = model.snapshot else { return [] }
        let toggles = Dictionary(uniqueKeysWithValues: snapshot.config.featureToggles.map { ($0.feature, $0) })
        return snapshot.capabilities.map { capability in
            AISettingsFeatureRowSnapshot(
                feature: capability.feature,
                enabled: toggles[capability.feature]?.enabled ?? capability.enabled,
                providerLabel: capability.feature.providerLabel,
                remoteScope: remoteScopeText(capability),
                disabledReason: capability.disabledReason
            )
        }
    }

    private var aiEnabledBinding: Binding<Bool> {
        Binding(
            get: { model.snapshot?.config.aiEnabled ?? false },
            set: { enabled in
                Task { await model.setAIEnabled(enabled) }
            }
        )
    }

    private var providerPreferenceBinding: Binding<AISettingsProviderPreference> {
        Binding(
            get: { model.snapshot?.config.providerPreference ?? .localFirst },
            set: { preference in
                Task { await model.setProviderPreference(preference) }
            }
        )
    }

    private func featureBinding(_ feature: AISettingsFeatureKind) -> Binding<Bool> {
        Binding(
            get: {
                model.snapshot?.config.featureToggles.first { $0.feature == feature }?.enabled ?? false
            },
            set: { enabled in
                Task { await model.setFeature(feature, enabled: enabled) }
            }
        )
    }

    private func isFeatureEditable(_ row: AISettingsFeatureRowSnapshot) -> Bool {
        model.snapshot?.config.aiEnabled == true && row.disabledReason != "AI is off"
    }

    private func remoteScopeText(_ capability: AISettingsCapabilitySnapshot) -> String {
        if capability.remoteAllowed { return "Remote scope allowed" }
        return "Remote scope blocked"
    }

    private func retryLoad() {
        Task { await model.load() }
    }

    private func retrySave() {
        Task { await model.retrySave() }
    }

    private func retryPause() {
        Task { await model.retryPause() }
    }

    private func pauseAllAI() {
        Task { await model.pauseAllAI() }
    }

    private func openLocalModelStatus() {
        model.openLocalModelStatusEntry()
        isLocalModelStatusPresented = true
    }
}
