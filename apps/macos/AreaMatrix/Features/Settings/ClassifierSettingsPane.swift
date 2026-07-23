import SwiftUI

struct ClassifierSettingsPane: View {
    @EnvironmentObject private var localizer: AppLocalizer
    @StateObject private var model: ClassifierSettingsModel
    @State private var showingRevertConfirmation = false
}

extension ClassifierSettingsPane {
    init(
        repoPath: String,
        loader: any CoreConfigurationLoading = AppCoreServices.configurationLoader,
        updater: any CoreConfigurationUpdating = AppCoreServices.configurationUpdater,
        predictor: any CoreCategoryPredicting = AppCoreServices.categoryPredictor,
        errorMapper: any CoreErrorMapping = AppCoreServices.errorMapper,
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
        SettingsPageHeader(title: L10n.string("settings.page.classifier"), subtitle: model.repoPath) {
            if model.isLoading {
                SettingsHeaderProgressIndicator(label: L10n.string("Checking classifier settings"))
            } else if model.isSaving {
                SettingsHeaderProgressIndicator(label: L10n.string("Saving classifier settings"))
            } else {
                Button("Retry status") {
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
            Button("Retry status") {
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
