import SwiftUI

struct ClassifierRuleEditorSection: View {
    @ObservedObject var model: ClassifierSettingsModel

    var body: some View {
        ClassifierSettingsSection(title: L10n.string("settings.classifier.section.visualRules")) {
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
                Label(L10n.string("settings.classifier.newCategory"), systemImage: "plus")
            }
            .disabled(!model.classifierRuleEditor.canCreateRule)
            .accessibilityIdentifier("classifier-rule-editor-new-category")

            Button {
                Task { await model.loadClassifierRuleEditor() }
            } label: {
                Label(L10n.string("Reload"), systemImage: "arrow.clockwise")
            }
            .disabled(model.classifierRuleEditor.isBusy)
            if let editingLocale = model.classifierRuleEditor.editingLocale {
                Picker(
                    L10n.string("settings.classifier.editingLanguage"),
                    selection: Binding(
                        get: { editingLocale },
                        set: { model.requestClassifierEditingLocale($0) }
                    )
                ) {
                    Text(L10n.string("settings.language.simplifiedChinese"))
                        .tag(ClassifierEditingLocale.zhHans)
                    Text(L10n.string("settings.language.english"))
                        .tag(ClassifierEditingLocale.en)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .accessibilityIdentifier("classifier-rule-editor-editing-language")
            }
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
            if model.classifierRuleEditor.health != .valid {
                classifierRecoveryPanel
            }
        case .loading:
            ProgressView(L10n.string("Loading classifier rules..."))
                .controlSize(.small)
                .accessibilityIdentifier("classifier-rule-editor-loading-classifier-rules")
        case let .failed(mapping):
            classifierRuleEditorError(mapping)
        }
        if case let .failed(mapping) = model.classifierRuleEditor.saveState {
            classifierRuleEditorError(mapping)
        }
        if case let .conflict(review) = model.classifierRuleEditor.saveState {
            classifierConflictReview(review)
        }
        if case .saved = model.classifierRuleEditor.saveState {
            Label(L10n.string("Classifier rule saved"), systemImage: "checkmark.circle")
                .foregroundStyle(.green)
                .accessibilityIdentifier("classifier-rule-editor-save-success")
        }
        switch model.classifierRuleEditor.recoveryState {
        case .idle:
            EmptyView()
        case let .recovering(action):
            ProgressView(recoveryProgressLabel(action))
                .controlSize(.small)
                .accessibilityIdentifier("classifier-rule-editor-recovery-progress")
        case let .succeeded(action):
            Label(recoverySuccessLabel(action), systemImage: "checkmark.circle")
                .foregroundStyle(.green)
                .accessibilityIdentifier("classifier-rule-editor-recovery-success")
        case let .failed(_, mapping):
            classifierRuleEditorError(mapping)
        }
        if let locale = model.classifierRuleEditor.pendingEditingLocale {
            classifierLocaleSwitchConfirmation(locale)
        }
    }

    private var classifierRecoveryPanel: some View {
        SettingsStatusBanner(
            title: recoveryHealthTitle,
            systemImage: "exclamationmark.triangle",
            tint: model.classifierRuleEditor.health == .unreadable ? .red : .orange
        ) {
            Text(recoveryHealthDetail)
                .font(.callout)
                .foregroundStyle(.secondary)

            if let pending = model.classifierRuleEditor.pendingRecoveryAction {
                Text(recoveryConfirmationDetail(pending))
                    .font(.callout)
                HStack(spacing: 10) {
                    Button(L10n.string("Cancel")) {
                        model.cancelClassifierRecovery()
                    }
                    Button(role: pending == .createDefault ? nil : .destructive) {
                        Task { await model.confirmClassifierRecovery() }
                    } label: {
                        Text(recoveryActionLabel(pending))
                    }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("classifier-rule-editor-confirm-recovery")
                }
            } else {
                HStack(spacing: 10) {
                    ForEach(model.classifierRuleEditor.recoveryActions) { action in
                        Button(recoveryActionLabel(action)) {
                            model.requestClassifierRecovery(action)
                        }
                        .accessibilityIdentifier("classifier-rule-editor-recovery-\(action.id)")
                    }
                }
            }
        }
        .accessibilityIdentifier("classifier-rule-editor-degraded-recovery")
    }

    private var recoveryHealthTitle: String {
        switch model.classifierRuleEditor.health {
        case .valid: L10n.string("settings.classifier.health.valid")
        case .missing: L10n.string("settings.classifier.health.missing")
        case .unreadable: L10n.string("settings.classifier.health.unreadable")
        case .invalid: L10n.string("settings.classifier.health.invalid")
        }
    }

    private var recoveryHealthDetail: String {
        switch model.classifierRuleEditor.health {
        case .valid: L10n.string("settings.classifier.health.valid.detail")
        case .missing: L10n.string("settings.classifier.health.missing.detail")
        case .unreadable: L10n.string("settings.classifier.health.unreadable.detail")
        case .invalid: L10n.string("settings.classifier.health.invalid.detail")
        }
    }

    private func recoveryActionLabel(_ action: ClassifierRecoveryActionState) -> String {
        switch action {
        case .createDefault: L10n.string("settings.classifier.recovery.createDefault.action")
        case .restoreDefault: L10n.string("settings.classifier.recovery.restoreDefault.action")
        case .restoreLastValid: L10n.string("settings.classifier.recovery.restoreLastValid.action")
        }
    }

    private func recoveryConfirmationDetail(_ action: ClassifierRecoveryActionState) -> String {
        switch action {
        case .createDefault: L10n.string("settings.classifier.recovery.createDefault.confirmation")
        case .restoreDefault: L10n.string("settings.classifier.recovery.restoreDefault.confirmation")
        case .restoreLastValid: L10n.string("settings.classifier.recovery.restoreLastValid.confirmation")
        }
    }

    private func recoveryProgressLabel(_ action: ClassifierRecoveryActionState) -> String {
        L10n.format("settings.classifier.recovery.progress", recoveryActionLabel(action))
    }

    private func recoverySuccessLabel(_ action: ClassifierRecoveryActionState) -> String {
        L10n.format("settings.classifier.recovery.success", recoveryActionLabel(action))
    }

    private func classifierLocaleSwitchConfirmation(_ locale: ClassifierEditingLocale) -> some View {
        SettingsStatusBanner(
            title: L10n.string("settings.classifier.unsavedLanguageDraft"),
            systemImage: "exclamationmark.triangle",
            tint: .orange
        ) {
            Text(L10n.format("settings.classifier.switchLanguageDetail", locale.rawValue))
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Button(L10n.string("Save and Switch")) {
                    Task { await model.saveAndSwitchClassifierEditingLocale() }
                }
                Button(L10n.string("Discard and Switch")) {
                    model.discardAndSwitchClassifierEditingLocale()
                }
                Button(L10n.string("Cancel")) {
                    model.cancelClassifierEditingLocaleSwitch()
                }
            }
        }
        .accessibilityIdentifier("classifier-rule-editor-language-switch-confirmation")
    }

    @ViewBuilder
    private var content: some View {
        if model.classifierRuleEditor.rules.isEmpty, model.classifierRuleEditor.draft == nil {
            ContentUnavailableView(L10n.string("No custom classifier rules yet"), systemImage: "tray")
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

    private func classifierConflictReview(_ review: ClassifierRuleConflictReview) -> some View {
        SettingsStatusBanner(
            title: L10n.string("settings.classifier.conflict.title"),
            systemImage: "exclamationmark.triangle",
            tint: .orange
        ) {
            Text(L10n.string("settings.classifier.conflict.detail"))
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 12) {
                classifierConflictColumn(
                    title: L10n.string("settings.classifier.conflict.latest"),
                    draft: review.latestDraft
                )
                classifierConflictColumn(
                    title: L10n.string("settings.classifier.conflict.local"),
                    draft: review.localDraft
                )
            }
            Text(L10n.string("settings.classifier.conflict.reviewRequirement"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(review.code)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
            HStack {
                Button(L10n.string("Reload latest")) {
                    model.reloadLatestClassifierRuleConflict()
                }
                Spacer()
                if review.latestDraft != nil {
                    Button(L10n.string("Review changes")) {
                        model.reviewLatestClassifierRuleConflict()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .accessibilityIdentifier("classifier-rule-editor-conflict-review")
    }

    private func classifierConflictColumn(
        title: String,
        draft: ClassifierRuleEditorDraft?
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption.weight(.semibold))
            if let draft {
                conflictRow(L10n.string("slug"), draft.slug)
                conflictRow(L10n.string("display name"), draft.displayName)
                conflictRow(L10n.string("description"), draft.description)
                conflictRow(L10n.string("Extensions"), draft.extensions.joined(separator: ", "))
                conflictRow(L10n.string("Keywords"), draft.keywords.joined(separator: ", "))
                conflictRow(L10n.string("Priority"), String(draft.priority))
                conflictRow(L10n.string("naming template"), draft.namingTemplate)
            } else {
                Text(L10n.string("settings.classifier.conflict.ruleMissing"))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
    }

    private func conflictRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value.isEmpty ? L10n.string("none") : value).font(.caption)
        }
    }
}
