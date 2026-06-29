import SwiftUI

struct ClassifierRuleEditorSection: View {
    @ObservedObject var model: ClassifierSettingsModel

    var body: some View {
        ClassifierSettingsSection(title: "可视化分类规则") {
            VStack(alignment: .leading, spacing: 12) {
                header
                status
                content
            }
            .accessibilityIdentifier("classifier-rule-editor-classifier-rule-editor")
        }
    }

    private var header: some View {
        HStack {
            Button { model.createClassifierRule() } label: {
                Label("New category", systemImage: "plus")
            }
            .disabled(model.classifierRuleEditor.isBusy)
            .accessibilityIdentifier("classifier-rule-editor-new-category")

            Button {
                Task { await model.loadClassifierRuleEditor() }
            } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .disabled(model.classifierRuleEditor.isBusy)
            Spacer()
        }
    }

    @ViewBuilder
    private var status: some View {
        switch model.classifierRuleEditor.loadState {
        case .idle, .loaded:
            if let warning = model.classifierRuleEditor.warning {
                Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
        case .loading:
            ProgressView("Loading classifier rules...")
                .controlSize(.small)
                .accessibilityIdentifier("classifier-rule-editor-loading-classifier-rules")
        case let .failed(mapping):
            classifierRuleEditorError(mapping)
        }
        if case let .failed(mapping) = model.classifierRuleEditor.saveState {
            classifierRuleEditorError(mapping)
        }
        if case .saved = model.classifierRuleEditor.saveState {
            Label("Classifier rule saved", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
                .accessibilityIdentifier("classifier-rule-editor-save-success")
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.classifierRuleEditor.rules.isEmpty, model.classifierRuleEditor.draft == nil {
            ContentUnavailableView("No custom classifier rules yet", systemImage: "tray")
        } else {
            HStack(alignment: .top, spacing: 16) {
                ClassifierRuleListView(model: model)
                ClassifierRuleDetailView(model: model)
            }
        }
    }

    private func classifierRuleEditorError(_ mapping: CoreErrorMappingSnapshot) -> some View {
        SettingsStatusBanner(title: mapping.userMessage, systemImage: "exclamationmark.triangle", tint: .red) {
            Text(mapping.suggestedAction)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("classifier-rule-editor-error")
    }
}
