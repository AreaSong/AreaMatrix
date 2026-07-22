import SwiftUI

struct RepositorySettingsConfigSection: View {
    let config: RepoConfigSnapshot?
    @ObservedObject var model: RepositorySettingsConfigModel
    let capabilityState: RepositorySettingsCapabilityState
    let onSaved: () async -> Void
    @State private var draft: RepositorySettingsConfigDraft

    init(
        config: RepoConfigSnapshot?,
        model: RepositorySettingsConfigModel,
        capabilityState: RepositorySettingsCapabilityState,
        onSaved: @escaping () async -> Void
    ) {
        self.config = config
        self.model = model
        self.capabilityState = capabilityState
        self.onSaved = onSaved
        _draft = State(initialValue: config.map(RepositorySettingsConfigDraft.init(config:)) ?? .empty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Repository config")
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: config) { _, newConfig in
            draft = newConfig.map(RepositorySettingsConfigDraft.init(config:)) ?? .empty
            model.resetFeedback()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let config {
            RepositorySettingsConfigValueRow(label: L10n.string("Default import mode"), value: config.defaultMode)
            RepositorySettingsConfigValueRow(
                label: L10n.string("AI"),
                value: config.aiEnabled ? L10n.string("Enabled") : L10n.string("Disabled")
            )
            RepositorySettingsConfigValueRow(
                label: L10n.string("Replace default"),
                value: config.allowReplaceDuringImport ? L10n.string("Allowed") : L10n.string("Disabled")
            )
            controls
            saveFeedback
        } else {
            Text("Repository config is not available.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Overview output", selection: $draft.overviewOutput) {
                ForEach(RepositorySettingsConfigOverviewOutput.allCases) { output in
                    Text(output.label).tag(output)
                }
            }
            Picker(L10n.string("settings.language.content.title"), selection: $draft.contentLanguage) {
                ForEach(RepositoryContentLanguage.allCases) { language in
                    Text(L10n.string(language.labelKey)).tag(language)
                }
            }
            Toggle("Show cloud location warnings", isOn: $draft.iCloudWarn)
            Toggle("Fallback uncategorized files to inbox", isOn: $draft.fallbackToInbox)
            saveActions
        }
        .disabled(editingDisabledReason != nil)
    }

    private var saveActions: some View {
        HStack(spacing: 10) {
            Button(saveTitle) {
                Task {
                    guard let config else { return }
                    let didSave = await model.save(draft: draft, currentConfig: config)
                    if didSave {
                        await onSaved()
                    }
                }
            }
            .disabled(!canSave)
            .accessibilityIdentifier("repository-settings-repository-settings-core-save-repository-config")

            Button("Reset changes") {
                draft = config.map(RepositorySettingsConfigDraft.init(config:)) ?? .empty
                model.resetFeedback()
            }
            .disabled(!hasChanges || model.saveState.isSaving)
        }
    }

    @ViewBuilder
    private var saveFeedback: some View {
        if let reason = editingDisabledReason {
            Text(reason)
                .font(.callout)
                .foregroundStyle(.secondary)
        }

        switch model.saveState {
        case .idle:
            EmptyView()
        case .saving:
            Label("Saving repository settings...", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        case let .saved(message):
            SettingsStatusBanner(title: message, systemImage: "checkmark.circle", tint: .green)
        case let .failed(error):
            SettingsStatusBanner(title: error.message, systemImage: "exclamationmark.triangle", tint: .red) {
                Text(error.recovery)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var canSave: Bool {
        config != nil && hasChanges && editingDisabledReason == nil && !model.saveState.isSaving
    }

    private var hasChanges: Bool {
        guard let config else { return false }
        return draft != RepositorySettingsConfigDraft(config: config)
    }

    private var saveTitle: String {
        model.saveState.isSaving
            ? L10n.string("Saving repository settings...")
            : L10n.string("Save repository settings")
    }

    private var editingDisabledReason: String? {
        switch capabilityState {
        case .loading:
            L10n.string("Repository access capability is still loading.")
        case let .loaded(capabilities):
            capabilities.securityBookmark.uiEnabled
                ? nil
                : capabilities.securityBookmark.reason
                ?? L10n.string("Repository access is not available on this platform.")
        case let .failed(_, error):
            error.recovery
        }
    }
}

private struct RepositorySettingsConfigValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
                .accessibilityLabel(L10n.format("settings.repository.valueAccessibility", label, value))
        }
        .font(.callout)
    }
}
