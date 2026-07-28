import SwiftUI

struct LanguageSettingsPane: View {
    @EnvironmentObject private var localizer: AppLocalizer
    @EnvironmentObject private var languageStore: AppLanguageStore
    @StateObject private var configModel: RepositorySettingsConfigModel
    @StateObject private var capabilityModel: RepoPlatformCapabilitiesModel
    @StateObject private var overviewModel: RepositoryOverviewRegenerationModel
    @State private var baseline: AppRepoConfigSnapshot?
    @State private var draft = RepositorySettingsConfigDraft.empty

    init(
        repoPath: String,
        loader: any CoreConfigurationLoading = AppCoreServices.configurationLoader,
        updater: any CoreConfigurationUpdating = AppCoreServices.configurationUpdater,
        capabilityLoader: any CorePlatformCapabilitiesLoading = AppCoreServices.platformCapabilityLoader,
        overviewRegenerator: any CoreOverviewRegenerating = AppCoreServices.overviewRegenerator,
        overviewRegenerationCoordinator: OverviewRegenerationCoordinator? = nil,
        appVersion: String? = nil,
        appVersionReader: any AppVersionReading = RepositorySettingsPlatformServices.appVersionReader,
        errorMapper: any CoreErrorMapping = AppCoreServices.errorMapper,
        accessibilityAnnouncer: any AccessibilityAnnouncing = RepositorySettingsPlatformServices.accessibilityAnnouncer
    ) {
        _configModel = StateObject(wrappedValue: RepositorySettingsConfigModel(
            repoPath: repoPath,
            loader: loader,
            updater: updater,
            errorMapper: errorMapper,
            accessibilityAnnouncer: accessibilityAnnouncer
        ))
        _capabilityModel = StateObject(wrappedValue: RepoPlatformCapabilitiesModel(
            appVersion: appVersion,
            appVersionReader: appVersionReader,
            capabilityLoader: capabilityLoader,
            errorMapper: errorMapper
        ))
        _overviewModel = StateObject(wrappedValue: RepositoryOverviewRegenerationModel(
            repoPath: repoPath,
            bridge: overviewRegenerator,
            coordinator: overviewRegenerationCoordinator,
            errorMapper: errorMapper
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsPageHeader(
                title: L10n.string("settings.page.language"),
                subtitle: configModel.repoPath
            ) {
                if configModel.isLoading || capabilityModel.isLoading {
                    SettingsHeaderProgressIndicator(label: L10n.string("settings.language.loading"))
                }
            }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await load() }
        .onChange(of: configModel.loadedConfig) { _, config in
            adopt(config)
        }
        .onChange(of: languageStore.resolvedResourceLocaleIdentifier) { _, _ in
            Task { await refreshOverviewStatus() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if configModel.isLoading, baseline == nil {
            SettingsPageLoadingContent(title: L10n.string("settings.language.loading"))
        } else if let error = configModel.loadError, baseline == nil {
            SettingsPageErrorContent(
                title: L10n.string("settings.language.loadError"),
                message: localizer.resolve(error.message),
                recovery: localizer.resolve(error.recovery)
            ) {
                Button(L10n.string("settings.action.retry")) { Task { await load() } }
            }
        } else {
            SettingsPageScrollContent {
                interfaceLanguageSection
                repositoryContentLanguageSection
                overviewLanguageSection
            }
        }
    }

    private var interfaceLanguageSection: some View {
        SettingsFormSection(title: L10n.string("settings.language.interface.title")) {
            Picker(L10n.string("settings.language.interface.title"), selection: interfaceLanguageSelection) {
                ForEach(AppLanguage.allCases) { language in
                    Text(localizer.resolve(language.displayMessage)).tag(language)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)
            .accessibilityIdentifier("language-settings-interface-language-picker")
            Text(L10n.string("settings.language.interface.description"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var repositoryContentLanguageSection: some View {
        SettingsFormSection(title: L10n.string("settings.language.content.title")) {
            if baseline != nil {
                contentLanguageControls
                saveFeedback
            } else {
                Text(L10n.string("Repository config is not available."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var contentLanguageControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(L10n.string("settings.language.content.title"), selection: $draft.contentLanguage) {
                if draft.contentLanguage.unsupportedIdentifier != nil {
                    Text(localizer.resolve(draft.contentLanguage.displayMessage)).tag(draft.contentLanguage)
                }
                ForEach(RepositoryContentLanguage.allCases) { language in
                    Text(localizer.resolve(language.displayMessage)).tag(language)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)
            .disabled(editingDisabledReason != nil)
            .accessibilityIdentifier("language-settings-content-language-picker")
            Text(L10n.string("settings.language.content.description"))
                .font(.callout)
                .foregroundStyle(.secondary)
            if let resolvedContentLocale {
                LabeledContent(L10n.string("settings.language.resolvedContentLanguage")) {
                    Text(localeLabel(resolvedContentLocale))
                }
            }
            if draft.contentLanguage.unsupportedIdentifier != nil {
                Text(L10n.string("settings.language.unsupportedExplanation"))
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 10) {
                Button(saveTitle) { Task { await saveContentLanguage() } }
                    .disabled(!canSave)
                    .accessibilityIdentifier("language-settings-save-content-language")
                Button(L10n.string("Reset changes"), action: resetDraft)
                    .disabled(!hasChanges || configModel.saveState.isSaving)
            }
            if let editingDisabledReason {
                Text(editingDisabledReason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var overviewLanguageSection: some View {
        if hasChanges {
            SettingsFormSection(title: L10n.string("settings.repository.overview.section")) {
                Text(L10n.string("settings.language.saveBeforeRegeneration"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } else if draft.contentLanguage.unsupportedIdentifier == nil {
            RepositoryOverviewRegenerationSection(model: overviewModel)
        } else {
            SettingsFormSection(title: L10n.string("settings.repository.overview.section")) {
                Text(L10n.string("settings.language.unsupportedExplanation"))
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var saveFeedback: some View {
        switch configModel.saveState {
        case .idle:
            EmptyView()
        case .saving:
            SettingsProgressBanner(title: L10n.string("Saving repository settings..."))
        case let .saved(message):
            SettingsStatusBanner(title: localizer.resolve(message), systemImage: "checkmark.circle", tint: .green) {
                Text(L10n.string("settings.language.existingContentUnchanged"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
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
            Text(L10n.string("settings.repository.conflict.reviewDetail"))
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button(L10n.string("settings.repository.conflict.reload")) {
                    baseline = conflict.latest
                    draft = RepositorySettingsConfigDraft(config: conflict.latest)
                    configModel.resetFeedback()
                }
                Button(L10n.string("settings.repository.conflict.review")) {
                    baseline = conflict.latest
                    draft = conflict.local.rebased(onto: conflict.latest, preserving: [.contentLanguage])
                    configModel.resetFeedback()
                }
            }
        }
        .accessibilityIdentifier("language-settings-config-revision-conflict")
    }

    private var interfaceLanguageSelection: Binding<AppLanguage> {
        Binding(get: { languageStore.selection }, set: languageStore.select)
    }

    private var hasChanges: Bool {
        guard let baseline else { return false }
        return draft.contentLanguage.snapshotValue != baseline.locale
    }

    private var canSave: Bool {
        baseline != nil && hasChanges && editingDisabledReason == nil && !configModel.saveState.isSaving
    }

    private var saveTitle: String {
        configModel.saveState.isSaving
            ? L10n.string("Saving repository settings...")
            : L10n.string("settings.language.saveContentLanguage")
    }

    private var resolvedContentLocale: String? {
        try? draft.contentLanguage.resolvedIdentifier(
            interfaceLocaleIdentifier: languageStore.resolvedResourceLocaleIdentifier
        )
    }

    private var editingDisabledReason: String? {
        switch capabilityModel.state {
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

    private func load() async {
        async let configLoad: Void = configModel.load()
        async let capabilityLoad: Void = capabilityModel.load()
        _ = await (configLoad, capabilityLoad)
        adopt(configModel.loadedConfig)
        await refreshOverviewStatus()
    }

    private func adopt(_ config: AppRepoConfigSnapshot?) {
        guard let config else { return }
        let hasLocalChanges = baseline.map { draft.contentLanguage.snapshotValue != $0.locale } ?? false
        guard !hasLocalChanges, !configModel.saveState.isSaving else { return }
        baseline = config
        draft = RepositorySettingsConfigDraft(config: config)
    }

    private func saveContentLanguage() async {
        guard let baseline else { return }
        let didSave = await configModel.saveContentLanguage(
            draft.contentLanguage,
            currentConfig: baseline
        )
        guard didSave, let saved = configModel.lastSavedConfig else { return }
        self.baseline = saved
        draft = RepositorySettingsConfigDraft(config: saved)
        await refreshOverviewStatus()
    }

    private func resetDraft() {
        guard let baseline else { return }
        draft = RepositorySettingsConfigDraft(config: baseline)
        configModel.resetFeedback()
    }

    private func refreshOverviewStatus() async {
        guard let baseline,
              let resolvedContentLocale = try? RepositoryContentLanguage(snapshotValue: baseline.locale)
              .resolvedIdentifier(interfaceLocaleIdentifier: languageStore.resolvedResourceLocaleIdentifier)
        else { return }
        await overviewModel.load(contentLocale: resolvedContentLocale)
    }

    private func localeLabel(_ identifier: String) -> String {
        identifier == "zh-Hans"
            ? L10n.string("settings.language.simplifiedChinese")
            : L10n.string("settings.language.english")
    }
}
