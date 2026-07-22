import SwiftUI

struct InitFailedStepView: View {
    let repoPath: String
    let mapping: CoreErrorMappingSnapshot?
    let diagnostics: InitializationDiagnosticsState
    let canRetry: Bool
    let onChangePath: () -> Void
    let onRetry: () -> Void
    let onCollectDiagnostics: () async -> Void
    let onQuit: () -> Void

    @State private var isDetailsExpanded = false
    @State private var isDiagnosticsPrivacyPresented = false

    var body: some View {
        VStack(alignment: .center, spacing: 28) {
            header

            VStack(spacing: 20) {
                errorSummary
                recoveryAdvice
                diagnosticsSection
            }
            .frame(maxWidth: 440)

            footer
        }
        .areaMatrixOnboardingPanel()
        .areaMatrixPageContentEntrance(delay: AreaMatrixMotionTokens.EntranceDelay.body)
        .confirmationDialog(
            L10n.string("onboarding.failed.collectDiagnostics"),
            isPresented: $isDiagnosticsPrivacyPresented
        ) {
            Button(L10n.string("onboarding.failed.collectDiagnosticsButton")) {
                Task { await onCollectDiagnostics() }
            }
            Button(L10n.string("settings.action.cancel"), role: .cancel) {}
        } message: {
            Text(
                "Repository diagnostics copy AreaMatrix metadata and may include paths, file names, tags, " +
                    "notes, and other sensitive metadata. Original file contents are not copied, and " +
                    "diagnostics are not uploaded automatically. Review the snapshot before sharing."
            )
        }
    }

    private var header: some View {
        AreaMatrixStepHeader(
            systemImage: "exclamationmark.triangle",
            tint: AreaMatrixTheme.Colors.coral,
            title: L10n.string("onboarding.failed.title"),
            subtitle: L10n.string("onboarding.failed.subtitle")
        )
    }

    private var errorSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("onboarding.failed.errorSummary"))
                .font(.headline)
            Text(mapping?.userMessage ?? L10n.string("Unknown initialization error"))
            Text("路径：\(repoPath)")
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
            Text(L10n.format(
                "onboarding.failed.errorCode",
                mapping?.kind.rawValue ?? L10n.string("Unknown")
            ))
            Text(L10n.format(
                "onboarding.failed.severity",
                mapping?.severity.rawValue ?? L10n.string("Unknown")
            ))
            DisclosureGroup("Show details", isExpanded: $isDetailsExpanded) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.format(
                        "onboarding.failed.recoverability",
                        mapping?.recoverability.rawValue ?? L10n.string("Unknown")
                    ))
                    Text("Raw context: \(mapping?.rawContext ?? repoPath)")
                        .textSelection(.enabled)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .areaMatrixGlassCard()
    }

    private var recoveryAdvice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("onboarding.failed.recoveryAdvice"))
                .font(.headline)
            Text(mapping?.suggestedAction ??
                L10n.string("onboarding.failed.defaultRecoveryAdvice"))
        }
        .font(.callout)
        .frame(maxWidth: 720, alignment: .leading)
    }

    @ViewBuilder
    private var diagnosticsSection: some View {
        switch diagnostics {
        case .idle, .confirmingPrivacy:
            EmptyView()
        case .collecting:
            Label("Preparing repository diagnostics...", systemImage: "arrow.clockwise")
                .font(.callout)
                .foregroundStyle(.secondary)
        case let .collected(snapshot):
            collectedDiagnostics(snapshot)
        case let .failed(mapping):
            failedDiagnostics(mapping)
        }
    }

    private func collectedDiagnostics(_ snapshot: DiagnosticsSnapshotSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Diagnostics collected", systemImage: "doc.badge.gearshape")
                .font(.headline)
            Text(snapshot.snapshotPath)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
            ForEach(snapshot.warnings.prefix(3), id: \.self) { warning in
                Text(warning)
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .areaMatrixGlassCard()
    }

    private func failedDiagnostics(_ mapping: CoreErrorMappingSnapshot) -> some View {
        TintedOutlinedStatusBanner(tint: .red) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Diagnostics could not be collected", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                Text(mapping.userMessage)
                Text(mapping.suggestedAction)
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        }
    }

    private var footer: some View {
        HStack {
            Button(action: onQuit) { Text(L10n.string("onboarding.failed.quit")) }
                .buttonStyle(AreaMatrixSecondaryButtonStyle())

            Spacer()

            Button(L10n.string("onboarding.failed.diagnostics")) {
                isDiagnosticsPrivacyPresented = true
            }
            .buttonStyle(AreaMatrixSecondaryButtonStyle())
            .controlSize(.large)
            .disabled(isActionInFlight)

            Button(L10n.string("onboarding.failed.changeLocation"), action: onChangePath)
                .buttonStyle(AreaMatrixSecondaryButtonStyle())
                .controlSize(.large)
                .disabled(isActionInFlight)

            Button(L10n.string("onboarding.failed.retry"), action: onRetry)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(AreaMatrixPrimaryButtonStyle(accent: AreaMatrixTheme.Colors.coral))
                .controlSize(.large)
                .disabled(!canRetry || isActionInFlight)
        }
        .frame(maxWidth: 440)
        .padding(.top, 16)
    }

    private var isActionInFlight: Bool {
        if case .collecting = diagnostics {
            return true
        }
        return false
    }
}
