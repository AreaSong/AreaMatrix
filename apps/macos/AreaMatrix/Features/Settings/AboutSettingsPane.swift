import SwiftUI

struct AboutSettingsPane: View {
    @StateObject private var model: AboutSettingsModel
    private let onOpenRepositorySettings: () -> Void
    private let onClose: () -> Void

    init(
        repoPath: String,
        appVersionReader: any AppVersionReading = BundleAppVersionReader(),
        coreVersionReader: any CoreVersionReading = CoreBridge(),
        metadataReader: any ExistingRepositoryMetadataReading = SQLiteExistingRepositoryMetadataReader(),
        diagnosticsExporter: any AboutDiagnosticsExporting = LocalAboutDiagnosticsExporter(),
        externalLinkOpener: any AboutExternalLinkOpening = NSWorkspaceAboutExternalLinkOpener(),
        logsOpener: any AboutLogsOpening = NSWorkspaceAboutLogsOpener(),
        stringCopier: any AboutStringCopying = NSPasteboardAboutStringCopier(),
        diagnosticsRevealer: any AboutDiagnosticsRevealing = NSWorkspaceAboutDiagnosticsRevealer(),
        errorMapper: any CoreErrorMapping = LocalAboutCoreErrorMapper(),
        accessibilityAnnouncer: any AccessibilityAnnouncing = VoiceOverAccessibilityAnnouncer(),
        onOpenRepositorySettings: @escaping () -> Void = {},
        onClose: @escaping () -> Void = {}
    ) {
        _model = StateObject(wrappedValue: AboutSettingsModel(
            repoPath: repoPath,
            appVersionReader: appVersionReader,
            coreVersionReader: coreVersionReader,
            metadataReader: metadataReader,
            diagnosticsExporter: diagnosticsExporter,
            externalLinkOpener: externalLinkOpener,
            logsOpener: logsOpener,
            stringCopier: stringCopier,
            diagnosticsRevealer: diagnosticsRevealer,
            errorMapper: errorMapper,
            accessibilityAnnouncer: accessibilityAnnouncer
        ))
        self.onOpenRepositorySettings = onOpenRepositorySettings
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
                    diagnosticsButtonTitle: model.diagnosticsButtonTitle,
                    diagnosticsState: model.diagnosticsState,
                    onRequestDiagnostics: model.requestDiagnosticsExport,
                    onRevealDiagnostics: model.revealDiagnostics,
                    onCopyDiagnosticsPath: model.copyDiagnosticsPath,
                    onCopyError: model.copyActionDetail
                )
                AboutSettingsLogsSection(
                    isDisabled: model.diagnosticsState.isCollecting,
                    logsPath: model.logsPath,
                    onOpenLogs: model.openLogs,
                    onCopyLogsPath: model.copyLogsPath
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await model.load()
        }
        .confirmationDialog(
            "Collect diagnostics?",
            isPresented: diagnosticsConfirmationBinding
        ) {
            Button("Cancel", role: .cancel, action: model.cancelDiagnosticsExport)
            Button("Collect diagnostics") {
                Task {
                    await model.collectDiagnostics()
                }
            }
        } message: {
            Text("Diagnostics do not include your original file contents and are not uploaded automatically.")
        }
    }

    @ViewBuilder
    private var versionErrorBanner: some View {
        if let error = model.versionError {
            AboutSettingsBanner(error: error, tint: .orange) {
                Button("Copy error") {
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
                SettingsStatusBanner(title: message, systemImage: "checkmark.circle", tint: .green)
            case let .failed(error):
                AboutSettingsBanner(error: error, tint: .red) {
                    Button("Copy detail") {
                        model.copyActionDetail(error)
                    }
                }
            }
        }
    }

    private var diagnosticsConfirmationBinding: Binding<Bool> {
        Binding(
            get: { model.diagnosticsState.isConfirmingPrivacy },
            set: { isPresented in
                if !isPresented {
                    model.cancelDiagnosticsExport()
                }
            }
        )
    }
}
