import SwiftUI

struct RepositorySettingsConfigSection: View {
    @EnvironmentObject private var localizer: AppLocalizer
    let config: AppRepoConfigSnapshot?
    @ObservedObject var model: RepositorySettingsConfigModel
    let capabilityState: RepositorySettingsCapabilityState
    let onSaved: () async -> Void
    @State private var draft: RepositorySettingsConfigDraft
    @State private var baseline: AppRepoConfigSnapshot?

    init(
        config: AppRepoConfigSnapshot?,
        model: RepositorySettingsConfigModel,
        capabilityState: RepositorySettingsCapabilityState,
        onSaved: @escaping () async -> Void
    ) {
        self.config = config
        self.model = model
        self.capabilityState = capabilityState
        self.onSaved = onSaved
        _draft = State(initialValue: config.map(RepositorySettingsConfigDraft.init(config:)) ?? .empty)
        _baseline = State(initialValue: config)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Repository config")
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: config) { _, newConfig in
            let hasLocalChanges = baseline.map { !draft.dirtyFields(comparedTo: $0).isEmpty } ?? false
            guard !hasLocalChanges, !model.saveState.isSaving else { return }
            baseline = newConfig
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
                if draft.contentLanguage.unsupportedIdentifier != nil {
                    Text(localizer.resolve(draft.contentLanguage.displayMessage)).tag(draft.contentLanguage)
                }
                ForEach(RepositoryContentLanguage.allCases) { language in
                    Text(localizer.resolve(language.displayMessage)).tag(language)
                }
            }
            .accessibilityIdentifier("repository-settings-content-language-picker")
            Text(L10n.string("settings.language.content.description"))
                .font(.callout)
                .foregroundStyle(.secondary)
            if draft.contentLanguage.unsupportedIdentifier != nil {
                Text(L10n.string("settings.language.unsupportedExplanation"))
                    .font(.callout)
                    .foregroundStyle(.orange)
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
                    guard let baseline else { return }
                    let dirtyFields = draft.dirtyFields(comparedTo: baseline)
                    let didSave = await model.save(
                        draft: draft,
                        currentConfig: baseline,
                        dirtyFields: dirtyFields
                    )
                    if didSave {
                        if let savedConfig = model.lastSavedConfig {
                            self.baseline = savedConfig
                            draft = RepositorySettingsConfigDraft(config: savedConfig)
                        }
                        await onSaved()
                    }
                }
            }
            .disabled(!canSave)
            .accessibilityIdentifier("repository-settings-repository-settings-core-save-repository-config")

            Button("Reset changes") {
                draft = baseline.map(RepositorySettingsConfigDraft.init(config:)) ?? .empty
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
            SettingsStatusBanner(title: localizer.resolve(message), systemImage: "checkmark.circle", tint: .green)
        case let .conflict(conflict):
            conflictReview(conflict)
        case let .failed(error):
            SettingsStatusBanner(
                title: localizer.resolve(error.message),
                systemImage: "exclamationmark.triangle",
                tint: .red
            ) {
                Text(localizer.resolve(error.recovery))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var canSave: Bool {
        baseline != nil && hasChanges && editingDisabledReason == nil && !model.saveState.isSaving
    }

    private var hasChanges: Bool {
        guard let baseline else { return false }
        return !draft.dirtyFields(comparedTo: baseline).isEmpty
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
            localizer.resolve(error.recovery)
        }
    }

    private func conflictReview(_ conflict: RepositorySettingsConfigConflict) -> some View {
        SettingsStatusBanner(
            title: L10n.string("settings.repository.conflict.title"),
            systemImage: "arrow.triangle.2.circlepath",
            tint: .orange
        ) {
            Text(L10n.format(
                "settings.repository.conflict.revisions",
                conflict.expectedRevision,
                conflict.currentRevision
            ))
            .font(.callout)
            .foregroundStyle(.secondary)

            ForEach(RepositorySettingsConfigField.allCases.filter(conflict.dirtyFields.contains)) { field in
                VStack(alignment: .leading, spacing: 3) {
                    Text(field.label).font(.callout.weight(.semibold))
                    Text(L10n.format("settings.repository.conflict.saved", field.value(in: conflict.saved)))
                    Text(L10n.format("settings.repository.conflict.latest", field.value(in: conflict.latest)))
                    Text(L10n.format("settings.repository.conflict.local", field.value(in: conflict.local)))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Text(L10n.string("settings.repository.conflict.reviewDetail"))
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button(L10n.string("settings.repository.conflict.reload")) {
                    baseline = conflict.latest
                    draft = RepositorySettingsConfigDraft(config: conflict.latest)
                    model.resetFeedback()
                }
                Button(L10n.string("settings.repository.conflict.review")) {
                    baseline = conflict.latest
                    draft = conflict.local.rebased(
                        onto: conflict.latest,
                        preserving: conflict.dirtyFields
                    )
                    model.resetFeedback()
                }
            }
        }
        .accessibilityIdentifier("repository-settings-config-revision-conflict")
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
