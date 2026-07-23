import SwiftUI

struct ClassifierSettingsLoadedContent: View {
    @EnvironmentObject private var localizer: AppLocalizer
    @ObservedObject var model: ClassifierSettingsModel
    @Binding var showingRevertConfirmation: Bool

    var body: some View {
        SettingsPageScrollContent {
            ClassifierSettingsSaveErrorBanner(model: model)
            ClassifierSettingsConfigPathSection(model: model)
            ClassifierRuleEditorSection(model: model)
            ClassifierSettingsRulesSection(model: model)
            ClassifierSettingsYAMLActionsSection(
                model: model,
                showingRevertConfirmation: $showingRevertConfirmation
            )
            ClassifierSettingsPreviewSection(model: model)
        }
    }
}

private struct ClassifierSettingsConfigPathSection: View {
    @ObservedObject var model: ClassifierSettingsModel

    var body: some View {
        ClassifierSettingsSection(title: L10n.string("settings.classifier.section.configPath")) {
            ClassifierSettingsKeyValueRow(
                label: L10n.string("classifier.yaml"),
                value: model.classifierConfigPath
            )
            ClassifierSettingsKeyValueRow(
                label: L10n.string("settings.classifier.label.validation"),
                value: model.validationStatusLabel
            )
        }
    }
}

private struct ClassifierSettingsRulesSection: View {
    @ObservedObject var model: ClassifierSettingsModel

    var body: some View {
        ClassifierSettingsSection(title: L10n.string("settings.classifier.section.ruleEngine")) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enable extension rules", isOn: extensionRulesSelection)
                    .accessibilityIdentifier("classifier-settings-enable-extension-rules")
                Text("Match file extensions before falling back to inbox.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Toggle("Enable keyword rules", isOn: keywordRulesSelection)
                    .accessibilityIdentifier("classifier-settings-enable-keyword-rules")
                Text("Use keyword matching for the current repository configuration.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Toggle("Fallback to inbox", isOn: fallbackToInboxSelection)
                    .accessibilityIdentifier("classifier-settings-fallback-to-inbox")
                Text("Keep unmatched files in inbox.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .disabled(writesDisabled)

            Text(L10n.string("settings.classifier.repositoryScope"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var writesDisabled: Bool {
        model.isSaving || !model.isLoaded
    }

    private var extensionRulesSelection: Binding<Bool> {
        Binding(
            get: { model.draft?.enableExtensionRules ?? true },
            set: { isEnabled in
                Task {
                    await model.requestEnableExtensionRules(isEnabled)
                }
            }
        )
    }

    private var keywordRulesSelection: Binding<Bool> {
        Binding(
            get: { model.draft?.enableKeywordRules ?? true },
            set: { isEnabled in
                Task {
                    await model.requestEnableKeywordRules(isEnabled)
                }
            }
        )
    }

    private var fallbackToInboxSelection: Binding<Bool> {
        Binding(
            get: { model.draft?.fallbackToInbox ?? true },
            set: { isEnabled in
                Task {
                    await model.requestFallbackToInbox(isEnabled)
                }
            }
        )
    }
}

private struct ClassifierSettingsYAMLActionsSection: View {
    @EnvironmentObject private var localizer: AppLocalizer
    @ObservedObject var model: ClassifierSettingsModel
    @Binding var showingRevertConfirmation: Bool

    var body: some View {
        ClassifierSettingsSection(title: L10n.string("settings.classifier.section.yamlActions")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Button {
                        model.openClassifierYaml()
                    } label: {
                        Label("Open classifier.yaml", systemImage: "doc.text")
                    }
                    .disabled(model.isSaving)
                    .accessibilityIdentifier("classifier-settings-open-classifier-yaml")

                    Button {
                        model.revealClassifierYamlInFinder()
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }
                    .disabled(model.isSaving)
                    .accessibilityIdentifier("classifier-settings-reveal-classifier-yaml")

                    Button {
                        Task {
                            _ = await model.validateClassifierRules()
                        }
                    } label: {
                        if model.isValidating {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Validate")
                            }
                        } else {
                            Label("Validate", systemImage: "checkmark.circle")
                        }
                    }
                    .disabled(model.isSaving || model.isValidating)
                    .accessibilityLabel(L10n.string("Validate classifier rules"))
                    .accessibilityIdentifier("classifier-settings-validate-classifier-rules")

                    Button {
                        showingRevertConfirmation = true
                    } label: {
                        Label("Revert to last valid", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(!model.canRevertToLastValid || model.isSaving || model.isValidating)
                    .accessibilityIdentifier("classifier-settings-revert-classifier-rules")
                }

                if model.isValidating {
                    ProgressView("Validating...")
                        .controlSize(.small)
                        .accessibilityIdentifier("classifier-settings-classifier-validating")
                }

                if let error = model.fileActionError {
                    fileActionErrorView(error)
                }

                if let error = model.validationError {
                    validationErrorView(error)
                }
            }
        }
    }

    private func fileActionErrorView(_ error: ClassifierSettingsFileActionError) -> some View {
        SettingsStatusBanner(
            title: localizer.resolve(error.message),
            systemImage: "exclamationmark.triangle",
            tint: .red
        ) {
            Text(localizer.resolve(error.recovery))
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("Reveal in Finder") {
                    model.revealClassifierYamlInFinder()
                }
                .accessibilityIdentifier("classifier-settings-file-error-reveal-classifier-yaml")
                Button("Create default") {
                    Task {
                        await model.createDefaultClassifierYaml()
                    }
                }
                .accessibilityIdentifier("classifier-settings-file-error-create-default-classifier-yaml")
            }
        }
        .accessibilityIdentifier("classifier-settings-classifier-file-action-error")
    }

    private func validationErrorView(_ error: ClassifierSettingsValidationError) -> some View {
        SettingsStatusBanner(
            title: localizer.resolve(error.message),
            systemImage: "exclamationmark.triangle",
            tint: .red
        ) {
            Text(localizer.resolve(error.recovery))
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("Open classifier.yaml") {
                    model.openClassifierYaml()
                }
                Button("Reveal in Finder") {
                    model.revealClassifierYamlInFinder()
                }
                .accessibilityIdentifier("classifier-settings-validation-reveal-classifier-yaml")
                Button("Create default") {
                    Task {
                        await model.createDefaultClassifierYaml()
                    }
                }
                .accessibilityIdentifier("classifier-settings-validation-create-default-classifier-yaml")
            }
        }
        .accessibilityIdentifier("classifier-settings-classifier-validation-error")
    }
}

private struct ClassifierSettingsPreviewSection: View {
    @EnvironmentObject private var localizer: AppLocalizer
    @ObservedObject var model: ClassifierSettingsModel

    var body: some View {
        ClassifierSettingsSection(title: L10n.string("settings.classifier.section.preview")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    TextField("Invoice_2026Q1.pdf", text: previewFilenameBinding)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(L10n.string("Preview filename"))
                        .accessibilityIdentifier("classifier-settings-preview-filename")
                    Button {
                        Task {
                            await model.previewClassification()
                        }
                    } label: {
                        if model.isPreviewing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Preview", systemImage: "play.circle")
                        }
                    }
                    .disabled(previewButtonDisabled)
                    .accessibilityLabel(L10n.string("Preview classification"))
                    .accessibilityIdentifier("classifier-settings-preview-classify")
                }

                if let error = model.previewError {
                    previewErrorView(error)
                } else if let result = model.previewResult {
                    previewResultView(result)
                } else if model.isPreviewing {
                    ProgressView("Previewing...")
                        .controlSize(.small)
                }
            }
            .accessibilityIdentifier("classifier-settings-classify-preview")
        }
    }

    private func previewErrorView(_ error: ClassifierSettingsPreviewError) -> some View {
        SettingsStatusBanner(
            title: localizer.resolve(error.message),
            systemImage: "exclamationmark.triangle",
            tint: .red
        ) {
            Text(localizer.resolve(error.recovery))
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                Task {
                    await model.previewClassification()
                }
            } label: {
                Label("Retry preview", systemImage: "arrow.clockwise")
            }
            .disabled(previewButtonDisabled)
        }
        .accessibilityIdentifier("classifier-settings-preview-error")
    }

    private func previewResultView(_ result: ClassifyResultSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("settings.classifier.preview.result"))
                .font(.subheadline.weight(.semibold))
            ClassifierSettingsKeyValueRow(
                label: L10n.string("settings.classifier.label.category"),
                value: result.category
            )
            ClassifierSettingsKeyValueRow(
                label: L10n.string("settings.classifier.label.suggestedName"),
                value: result.suggestedName
            )
            ClassifierSettingsKeyValueRow(
                label: L10n.string("settings.classifier.label.reason"),
                value: result.reason.displayLabel
            )
            ClassifierSettingsKeyValueRow(
                label: L10n.string("settings.classifier.label.confidence"),
                value: L10n.format("settings.classifier.confidencePercent", result.confidencePercent)
            )
        }
        .accessibilityIdentifier("classifier-settings-preview-result")
    }

    private var previewButtonDisabled: Bool {
        model.isSaving || model.isPreviewing ||
            model.previewFilename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var previewFilenameBinding: Binding<String> {
        Binding(
            get: { model.previewFilename },
            set: { newValue in
                model.updatePreviewFilename(newValue)
            }
        )
    }
}

private struct ClassifierSettingsSaveErrorBanner: View {
    @EnvironmentObject private var localizer: AppLocalizer
    @ObservedObject var model: ClassifierSettingsModel

    var body: some View {
        if let error = model.saveError {
            SettingsStatusBanner(
                title: localizer.resolve(error.message),
                systemImage: "exclamationmark.triangle",
                tint: .red
            ) {
                Text(localizer.resolve(error.recovery))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("The UI has been restored to the last saved values.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if model.hasRetryableSave {
                    Button("Retry save") {
                        Task {
                            await model.retrySave()
                        }
                    }
                }
            }
        }
    }
}
