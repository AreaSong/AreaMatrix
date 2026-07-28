import SwiftUI

struct AboutSettingsPane: View {
    @EnvironmentObject private var localizer: AppLocalizer
    @StateObject private var model: AboutSettingsModel
    private let onOpenRepositorySettings: () -> Void
    private let onOpenDiagnostics: () -> Void
    private let onClose: () -> Void

    init(
        repoPath: String,
        appVersionReader: any AppVersionReading = AboutSettingsPlatformServices.appVersionReader,
        coreVersionReader: any CoreVersionReading = AppCoreServices.coreVersionReader,
        metadataReader: any ExistingRepositoryMetadataReading = AboutSettingsPlatformServices.metadataReader,
        externalLinkOpener: any AboutExternalLinkOpening = AboutSettingsPlatformServices.externalLinkOpener,
        stringCopier: any AboutStringCopying = AboutSettingsPlatformServices.stringCopier,
        errorMapper: any CoreErrorMapping = AppCoreServices.errorMapper,
        accessibilityAnnouncer: any AccessibilityAnnouncing = AboutSettingsPlatformServices.accessibilityAnnouncer,
        onOpenRepositorySettings: @escaping () -> Void = {},
        onOpenDiagnostics: @escaping () -> Void = {},
        onClose: @escaping () -> Void = {}
    ) {
        _model = StateObject(wrappedValue: AboutSettingsModel(
            repoPath: repoPath,
            appVersionReader: appVersionReader,
            coreVersionReader: coreVersionReader,
            metadataReader: metadataReader,
            externalLinkOpener: externalLinkOpener,
            stringCopier: stringCopier,
            errorMapper: errorMapper,
            accessibilityAnnouncer: accessibilityAnnouncer
        ))
        self.onOpenRepositorySettings = onOpenRepositorySettings
        self.onOpenDiagnostics = onOpenDiagnostics
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AboutSettingsHeader(
                repoPath: model.repoPath,
                isLoadingVersionInfo: model.isLoadingVersionInfo,
                onRetryVersionCheck: {
                    Task {
                        await model.load()
                    }
                }
            )
            SettingsPageScrollContent {
                versionErrorBanner
                actionFeedbackBanner
                AboutSettingsVersionsSection(
                    versionInfo: model.versionInfo,
                    onCopyVersions: model.copyVersionSummary
                )
                PlatformDifferencesView(
                    repositoryText: model.repoPath,
                    onOpenRepositorySettings: onOpenRepositorySettings,
                    onClose: onClose
                )
                AboutSettingsLicenseSection()
                AboutSettingsLinksSection(
                    onOpenLink: model.openExternalLink,
                    onCopyLink: model.copyExternalLink
                )
                AboutSettingsDiagnosticsSection(
                    onOpenDiagnostics: onOpenDiagnostics
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await model.load()
        }
    }

    @ViewBuilder
    private var versionErrorBanner: some View {
        if let error = model.versionError {
            AboutSettingsBanner(error: error, tint: .orange) {
                Button(L10n.string("Copy error")) {
                    model.copyActionDetail(error)
                }
            }
        }
    }

    @ViewBuilder
    private var actionFeedbackBanner: some View {
        if let feedback = model.actionFeedback {
            switch feedback {
            case let .success(message):
                SettingsStatusBanner(title: localizer.resolve(message), systemImage: "checkmark.circle", tint: .green)
            case let .failed(error):
                AboutSettingsBanner(error: error, tint: .red) {
                    Button(L10n.string("Copy detail")) {
                        model.copyActionDetail(error)
                    }
                }
            }
        }
    }
}
