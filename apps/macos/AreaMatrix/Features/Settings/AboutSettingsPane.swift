import AreaMatrixCoreBridgeContract
import SwiftUI

struct AboutSettingsPane: View {
    @EnvironmentObject private var localizer: AppLocalizer
    @StateObject private var model: AboutSettingsModel
    private let platformDifferencesModel: PlatformDifferencesModel
    private let onOpenRepositorySettings: () -> Void
    private let onOpenDiagnostics: () -> Void
    private let onClose: () -> Void

    init(
        repoPath: String,
        featureDependencies: SettingsFeatureDependencies,
        sharedDependencies: SharedFeatureDependencies,
        appVersionReader: (any AppVersionReading)? = nil,
        metadataReader: (any ExistingRepositoryMetadataReading)? = nil,
        externalLinkOpener: (any AboutExternalLinkOpening)? = nil,
        stringCopier: (any AboutStringCopying)? = nil,
        accessibilityAnnouncer: (any AccessibilityAnnouncing)? = nil,
        platformDifferencesModel: PlatformDifferencesModel,
        onOpenRepositorySettings: @escaping () -> Void = {},
        onOpenDiagnostics: @escaping () -> Void = {},
        onClose: @escaping () -> Void = {}
    ) {
        self.init(
            repoPath: repoPath,
            appVersionReader: appVersionReader ?? featureDependencies.appVersionReader,
            coreVersionReader: featureDependencies.coreVersionReader,
            metadataReader: metadataReader ?? featureDependencies.existingRepositoryMetadataReader,
            externalLinkOpener: externalLinkOpener ?? featureDependencies.aboutExternalLinkOpener,
            stringCopier: stringCopier ?? featureDependencies.aboutStringCopier,
            errorMapper: sharedDependencies.errorMapper,
            accessibilityAnnouncer: accessibilityAnnouncer ?? featureDependencies.accessibilityAnnouncer,
            platformDifferencesModel: platformDifferencesModel,
            onOpenRepositorySettings: onOpenRepositorySettings,
            onOpenDiagnostics: onOpenDiagnostics,
            onClose: onClose
        )
    }

    init(
        repoPath: String,
        appVersionReader: any AppVersionReading,
        coreVersionReader: any CoreVersionReading,
        metadataReader: any ExistingRepositoryMetadataReading,
        externalLinkOpener: any AboutExternalLinkOpening,
        stringCopier: any AboutStringCopying,
        errorMapper: any CoreErrorMapping,
        accessibilityAnnouncer: any AccessibilityAnnouncing,
        platformDifferencesModel: PlatformDifferencesModel,
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
        self.platformDifferencesModel = platformDifferencesModel
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
                platformDifferences
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

    private var platformDifferences: some View {
        PlatformDifferencesView(
            model: platformDifferencesModel,
            onOpenRepositorySettings: onOpenRepositorySettings,
            onClose: onClose
        )
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
