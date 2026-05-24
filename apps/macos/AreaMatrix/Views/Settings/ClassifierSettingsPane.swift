import SwiftUI

struct ClassifierSettingsPane: View {
    @StateObject private var model: ClassifierSettingsModel
    @State private var showingRevertConfirmation = false
}

extension ClassifierSettingsPane {
    init(
        repoPath: String,
        loader: any CoreConfigurationLoading = CoreBridge(),
        updater: any CoreConfigurationUpdating = CoreBridge(),
        predictor: any CoreCategoryPredicting = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge(),
        onSavedCategory: ((String) -> Void)? = nil
    ) {
        let settingsModel = ClassifierSettingsModel(
            repoPath: repoPath,
            loader: loader,
            updater: updater,
            predictor: predictor,
            errorMapper: errorMapper,
            onSavedCategory: onSavedCategory
        )
        _model = StateObject(wrappedValue: settingsModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await model.load()
        }
        .alert("Revert to last valid classifier.yaml?", isPresented: $showingRevertConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Revert", role: .destructive) {
                Task {
                    await model.revertToLastValid()
                }
            }
        } message: {
            Text("This replaces the current classifier.yaml with the last validated backup.")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("分类规则")
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
            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Checking classifier settings")
            } else if model.isSaving {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Saving classifier settings")
            } else {
                Button("Retry status") {
                    Task {
                        await model.load()
                    }
                }
                .accessibilityIdentifier("S1-28-classifier-retry-status")
            }
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 18)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.loadState {
        case .loading:
            loadingContent
        case .loaded:
            loadedContent
        case let .failed(error):
            loadErrorContent(error)
        }
    }

    private var loadingContent: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Checking classifier settings...")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadErrorContent(_ error: ClassifierSettingsLoadError) -> some View {
        ContentUnavailableView {
            Label("Unable to load classifier settings", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.message)
            Text(error.recovery)
        } actions: {
            Button("Retry status") {
                Task {
                    await model.load()
                }
            }
        }
    }

    private var loadedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                saveErrorBanner
                configPathSection
                rulesSection
                yamlActionsSection
                previewSection
            }
            .frame(maxWidth: 700, alignment: .leading)
            .padding(.horizontal, 34)
            .padding(.vertical, 28)
        }
    }

    private var configPathSection: some View {
        ClassifierSettingsSection(title: "配置路径") {
            ClassifierSettingsKeyValueRow(
                label: "classifier.yaml",
                value: model.classifierConfigPath
            )
            ClassifierSettingsKeyValueRow(
                label: "Validation",
                value: model.validationStatusLabel
            )
        }
    }

    private var rulesSection: some View {
        ClassifierSettingsSection(title: "规则引擎") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enable extension rules", isOn: extensionRulesSelection)
                    .accessibilityIdentifier("S1-28-enable-extension-rules")
                Text("Match file extensions before falling back to inbox.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Toggle("Enable keyword rules", isOn: keywordRulesSelection)
                    .accessibilityIdentifier("S1-28-enable-keyword-rules")
                Text("Use keyword matching for the current repository configuration.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Toggle("Fallback to inbox", isOn: fallbackToInboxSelection)
                    .accessibilityIdentifier("S1-28-fallback-to-inbox")
                Text("Keep unmatched files in inbox.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .disabled(writesDisabled)

            Text("这些开关写入当前资料库配置。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var yamlActionsSection: some View {
        ClassifierSettingsSection(title: "YAML 操作") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Button {
                        model.openClassifierYaml()
                    } label: {
                        Label("Open classifier.yaml", systemImage: "doc.text")
                    }
                    .disabled(model.isSaving)
                    .accessibilityIdentifier("S1-28-open-classifier-yaml")

                    Button {
                        model.revealClassifierYamlInFinder()
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }
                    .disabled(model.isSaving)
                    .accessibilityIdentifier("S1-28-reveal-classifier-yaml")

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
                    .accessibilityLabel("Validate classifier rules")
                    .accessibilityIdentifier("S1-28-validate-classifier-rules")

                    Button {
                        showingRevertConfirmation = true
                    } label: {
                        Label("Revert to last valid", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(!model.canRevertToLastValid || model.isSaving || model.isValidating)
                    .accessibilityIdentifier("S1-28-revert-classifier-rules")
                }

                if model.isValidating {
                    ProgressView("Validating...")
                        .controlSize(.small)
                        .accessibilityIdentifier("S1-28-classifier-validating")
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
        VStack(alignment: .leading, spacing: 8) {
            Label(error.message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
            Text(error.recovery)
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("Reveal in Finder") {
                    model.revealClassifierYamlInFinder()
                }
                .accessibilityIdentifier("S1-28-file-error-reveal-classifier-yaml")
                Button("Create default") {
                    Task {
                        await model.createDefaultClassifierYaml()
                    }
                }
                .accessibilityIdentifier("S1-28-file-error-create-default-classifier-yaml")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("S1-28-classifier-file-action-error")
    }

    private func validationErrorView(_ error: ClassifierSettingsValidationError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error.message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
            Text(error.recovery)
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("Open classifier.yaml") {
                    model.openClassifierYaml()
                }
                Button("Reveal in Finder") {
                    model.revealClassifierYamlInFinder()
                }
                .accessibilityIdentifier("S1-28-validation-reveal-classifier-yaml")
                Button("Create default") {
                    Task {
                        await model.createDefaultClassifierYaml()
                    }
                }
                .accessibilityIdentifier("S1-28-validation-create-default-classifier-yaml")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("S1-28-classifier-validation-error")
    }

    private var previewSection: some View {
        ClassifierSettingsSection(title: "分类预览") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    TextField("Invoice_2026Q1.pdf", text: previewFilenameBinding)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Preview filename")
                        .accessibilityIdentifier("S1-28-preview-filename")
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
                    .accessibilityLabel("Preview classification")
                    .accessibilityIdentifier("S1-28-preview-classify")
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
            .accessibilityIdentifier("S1-28-classify-preview")
        }
    }

    @ViewBuilder
    private var saveErrorBanner: some View {
        if let error = model.saveError {
            VStack(alignment: .leading, spacing: 8) {
                Label(error.message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text(error.recovery)
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
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine)
        }
    }

    private func previewErrorView(_ error: ClassifierSettingsPreviewError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error.message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
            Text(error.recovery)
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
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("S1-28-preview-error")
    }

    private func previewResultView(_ result: ClassifyResultSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("预览结果")
                .font(.subheadline.weight(.semibold))
            ClassifierSettingsKeyValueRow(label: "分类", value: result.category)
            ClassifierSettingsKeyValueRow(label: "建议名称", value: result.suggestedName)
            ClassifierSettingsKeyValueRow(label: "原因", value: result.reason.displayLabel)
            ClassifierSettingsKeyValueRow(label: "置信度", value: "\(result.confidencePercent)%")
        }
        .accessibilityIdentifier("S1-28-preview-result")
    }

    private var writesDisabled: Bool {
        model.isSaving || !model.isLoaded
    }

    private var previewButtonDisabled: Bool {
        model.isSaving || model.isPreviewing ||
            model.previewFilename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    private var previewFilenameBinding: Binding<String> {
        Binding(
            get: { model.previewFilename },
            set: { newValue in
                model.updatePreviewFilename(newValue)
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

private struct ClassifierSettingsSection<Content: View>: View {
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

private struct ClassifierSettingsKeyValueRow: View {
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
                .accessibilityLabel("\(label): \(value)")
        }
        .font(.callout)
    }
}
