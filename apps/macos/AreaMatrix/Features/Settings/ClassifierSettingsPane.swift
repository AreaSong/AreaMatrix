import SwiftUI

struct ClassifierSettingsPane: View {
    @EnvironmentObject private var localizer: AppLocalizer
    @StateObject private var model: ClassifierSettingsModel
    @State private var showingRevertConfirmation = false
}

extension ClassifierSettingsPane {
    init(model: ClassifierSettingsModel) {
        _model = StateObject(wrappedValue: model)
    }

    init(
        repoPath: String,
        featureDependencies: SettingsFeatureDependencies,
        sharedDependencies: SharedFeatureDependencies,
        onSavedCategory: ((String) -> Void)? = nil
    ) {
        self.init(
            repoPath: repoPath,
            loader: featureDependencies.configurationLoader,
            updater: featureDependencies.configurationUpdater,
            predictor: featureDependencies.categoryPredictor,
            ruleEditor: featureDependencies.classifierRuleEditor,
            interfaceLocaleIdentifier: featureDependencies.interfaceLocaleIdentifier,
            errorMapper: sharedDependencies.errorMapper,
            fileOpener: featureDependencies.classifierFileOpener,
            fileRevealer: featureDependencies.classifierFileRevealer,
            finderOpener: featureDependencies.classifierFinderOpener,
            accessibilityAnnouncer: featureDependencies.classifierAccessibilityAnnouncer,
            onSavedCategory: onSavedCategory
        )
    }

    init(
        repoPath: String,
        loader: any CoreConfigurationLoading,
        updater: any CoreConfigurationUpdating,
        predictor: any CoreCategoryPredicting,
        ruleEditor: any CoreClassifierRuleEditing,
        interfaceLocaleIdentifier: @escaping @MainActor () -> String = { "en" },
        errorMapper: any CoreErrorMapping,
        fileOpener: any RepositoryFileOpening,
        fileRevealer: any RepositoryFileRevealing,
        finderOpener: any RepositoryFinderOpening,
        accessibilityAnnouncer: any AccessibilityAnnouncing,
        onSavedCategory: ((String) -> Void)? = nil
    ) {
        let settingsModel = ClassifierSettingsModel(
            repoPath: repoPath,
            loader: loader,
            updater: updater,
            predictor: predictor,
            ruleEditor: ruleEditor,
            interfaceLocaleIdentifier: interfaceLocaleIdentifier,
            errorMapper: errorMapper,
            fileOpener: fileOpener,
            fileRevealer: fileRevealer,
            finderOpener: finderOpener,
            accessibilityAnnouncer: accessibilityAnnouncer,
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
        .onChange(of: localizer.resourceLocaleIdentifier) { _, _ in
            model.refreshInterfaceLocaleIdentifier()
        }
        .alert(L10n.string("Revert to last valid classifier.yaml?"), isPresented: $showingRevertConfirmation) {
            Button(L10n.string("Cancel"), role: .cancel) {}
            Button(L10n.string("Revert"), role: .destructive) {
                Task {
                    await model.revertToLastValid()
                }
            }
        } message: {
            Text(L10n.string("This replaces the current classifier.yaml with the last validated backup."))
        }
    }

    private var header: some View {
        SettingsPageHeader(title: L10n.string("settings.page.classifier"), subtitle: model.repoPath) {
            if model.isLoading {
                SettingsHeaderProgressIndicator(label: L10n.string("Checking classifier settings"))
            } else if model.isSaving {
                SettingsHeaderProgressIndicator(label: L10n.string("Saving classifier settings"))
            } else {
                Button(L10n.string("Retry status")) {
                    Task {
                        await model.load()
                    }
                }
                .accessibilityIdentifier("classifier-settings-classifier-retry-status")
            }
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
        SettingsPageLoadingContent(title: L10n.string("settings.loading.classifier"))
    }

    private func loadErrorContent(_ error: ClassifierSettingsLoadError) -> some View {
        SettingsPageErrorContent(
            title: L10n.string("settings.error.loadClassifier"),
            message: localizer.resolve(error.message),
            recovery: localizer.resolve(error.recovery)
        ) {
            Button(L10n.string("Retry status")) {
                Task {
                    await model.load()
                }
            }
        }
    }

    private var loadedContent: some View {
        ClassifierSettingsLoadedContent(
            model: model,
            showingRevertConfirmation: $showingRevertConfirmation
        )
    }
}
