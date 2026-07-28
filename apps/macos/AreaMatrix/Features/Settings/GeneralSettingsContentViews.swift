import SwiftUI

struct AppLanguageSettingsSheet: View {
    @EnvironmentObject private var localizer: AppLocalizer
    @EnvironmentObject private var languageStore: AppLanguageStore
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string("settings.language.section"))
                    .font(.title2.weight(.semibold))
                Text(L10n.string("settings.language.interface.description"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Picker(L10n.string("settings.language.interface.title"), selection: languageSelection) {
                ForEach(AppLanguage.allCases) { language in
                    Text(localizer.resolve(language.displayMessage)).tag(language)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("app-language-settings-interface-picker")

            Divider()

            HStack {
                Spacer()
                Button(L10n.string("settings.action.close"), action: onClose)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("app-language-settings-close")
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private var languageSelection: Binding<AppLanguage> {
        Binding(
            get: { languageStore.selection },
            set: languageStore.select
        )
    }
}

struct GeneralSettingsLoadedContent: View {
    @EnvironmentObject private var localizer: AppLocalizer
    @EnvironmentObject private var languageStore: AppLanguageStore
    @ObservedObject var model: GeneralSettingsModel
    let onOpenLanguageSettings: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            SettingsPageScrollContent {
                saveErrorBanner
                storageSection
                overviewSection
                ignoreRulesSection
                languageSection
                appearanceSection
            }
            footer
        }
    }

    private var header: some View {
        SettingsPageHeader(title: L10n.string("settings.page.general"), subtitle: model.repoPath) {
            if model.isSaving {
                SettingsHeaderProgressIndicator(label: L10n.string("Saving settings"))
            }
        }
    }

    @ViewBuilder
    private var saveErrorBanner: some View {
        if let error = model.saveError {
            SettingsStatusBanner(
                title: localizer.resolve(error.message),
                systemImage: "exclamationmark.triangle",
                tint: .red
            ) {
                Text(localizer.resolve(error.recovery))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(
                    """
                    The UI has been restored to the last saved settings. .areamatrix/generated/ remains the safe \
                    default overview output.
                    """
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                if model.hasRetryableSave {
                    Button(L10n.string("Retry save")) {
                        Task {
                            await model.retrySave()
                        }
                    }
                }
            }
        }
    }

    private var storageSection: some View {
        SettingsFormSection(title: L10n.string("settings.general.section.storage")) {
            Picker(L10n.string("Default storage mode"), selection: storageSelection) {
                ForEach(GeneralSettingsStorageMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)
            .disabled(writesDisabled)
            Text(L10n.string("导入时仍可在 ImportSheet 临时更改。"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var overviewSection: some View {
        SettingsFormSection(title: L10n.string("settings.general.section.overview")) {
            Picker(L10n.string("Repository overview output"), selection: overviewSelection) {
                Text(L10n.string("仅保存在 .areamatrix/generated/")).tag(GeneralSettingsOverviewOutput.generatedOnly)
                Text(L10n.string("同时在根目录生成 AREAMATRIX.md")).tag(GeneralSettingsOverviewOutput.rootAreaMatrixFile)
            }
            .pickerStyle(.radioGroup)
            .disabled(writesDisabled)
            Text(L10n.string("AreaMatrix 永远不会覆盖已有 README.md。"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var ignoreRulesSection: some View {
        SettingsFormSection(title: L10n.string("settings.general.section.ignoreRules")) {
            Button(L10n.string("Open ignore.yaml"), action: model.openIgnoreRules)
                .disabled(writesDisabled)
            Text(L10n.string("Missing ignore.yaml can be recreated only inside .areamatrix/."))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var languageSection: some View {
        SettingsFormSection(title: L10n.string("settings.language.section")) {
            LabeledContent(L10n.string("settings.language.interface.title")) {
                Text(localizer.resolve(languageStore.selection.displayMessage))
            }
            Button(L10n.string("settings.language.openSettings"), action: onOpenLanguageSettings)
                .accessibilityIdentifier("general-settings-open-language-settings")
        }
    }

    private var appearanceSection: some View {
        SettingsFormSection(title: L10n.string("settings.general.section.appearance")) {
            Picker(L10n.string("Appearance"), selection: .constant(GeneralSettingsAppearance.system)) {
                ForEach(GeneralSettingsAppearance.allCases) { appearance in
                    Text(appearance.label).tag(appearance)
                }
            }
            .pickerStyle(.segmented)
            .disabled(true)
            .frame(maxWidth: 180)
        }
    }

    private var footer: some View {
        HStack {
            Button(L10n.string("Reset this tab")) {
                Task {
                    await model.resetThisTab()
                }
            }
            .disabled(writesDisabled)
            Spacer()
            Button(L10n.string("settings.action.close"), action: onClose)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 16)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var writesDisabled: Bool {
        model.isSaving || !model.isLoaded || model.pendingStorageConfirmation != nil ||
            model.pendingRootOverviewStatus != nil || model.pendingIgnoreRulesAlert != nil
    }

    private var storageSelection: Binding<GeneralSettingsStorageMode> {
        Binding(
            get: { model.draft?.defaultStorageMode ?? .copy },
            set: { mode in
                Task {
                    await model.requestStorageMode(mode)
                }
            }
        )
    }

    private var overviewSelection: Binding<GeneralSettingsOverviewOutput> {
        Binding(
            get: { model.draft?.overviewOutput ?? .generatedOnly },
            set: { output in
                Task {
                    await model.requestOverviewOutput(output)
                }
            }
        )
    }
}

struct GeneralSettingsLoadingContent: View {
    let onClose: () -> Void

    var body: some View {
        SettingsPageLoadingContent(title: L10n.string("settings.loading.settings")) {
            Button(L10n.string("settings.action.close"), action: onClose)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("general-settings-loading-close-settings")
        }
    }
}

struct RootOverviewConfirmationSheet: View {
    let status: RootOverviewFileStatus
    let onCancel: () -> Void
    let onRevealInFinder: () -> Void
    let onEnable: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.string("Enable root AREAMATRIX.md?"))
                .font(.title2.weight(.semibold))
            Text(
                """
                AreaMatrix will continue writing generated overviews to .areamatrix/generated/. If AREAMATRIX.md \
                already exists, AreaMatrix will only update its own managed block after you confirm. README.md is \
                never used as an automatic output target.
                """
            )
            .fixedSize(horizontal: false, vertical: true)
            Text(status.confirmationDetail)
                .foregroundStyle(status.canEnableRootOverview ? Color.secondary : Color.red)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if status.requiresFinderRecovery {
                    Button(L10n.string("Reveal in Finder"), action: onRevealInFinder)
                }
                Spacer()
                Button(L10n.string("Cancel"), action: onCancel)
                Button(L10n.string("Enable root overview"), action: onEnable)
                    .buttonStyle(.borderedProminent)
                    .disabled(!status.canEnableRootOverview)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
