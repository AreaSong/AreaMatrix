import AreaMatrixCoreBridgeContract
import AreaMatrixUIFoundation
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
        VStack(alignment: .leading, spacing: 40) {
            header

            VStack(alignment: .leading, spacing: 20) {
                errorSummary
                recoveryAdvice
                diagnosticsSection
            }

            Spacer()
            footer
        }
        .frame(maxWidth: 580)
        .padding(.horizontal, 48)
        .padding(.vertical, 32)
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
            Text(L10n.string("diagnostics.repositoryPrivacyDetail"))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                AreaMatrixLucideIcon(name: .alertTriangle, lineWidth: 2)
                    .frame(width: 28, height: 28)
                    .foregroundStyle(AreaMatrixTheme.Colors.coral)
                    .background(
                        Circle()
                            .fill(AreaMatrixTheme.Colors.coral.opacity(0.1))
                            .frame(width: 48, height: 48)
                    )
                Text("INITIALIZATION FAILED")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundStyle(AreaMatrixTheme.Colors.coral)
                    .tracking(6)
            }
            .padding(.bottom, 8)

            Text(L10n.string("onboarding.failed.title"))
                .font(.system(size: 42, weight: .heavy))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            Text(L10n.string("onboarding.failed.subtitle"))
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 20)
    }

    private var errorSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("onboarding.failed.errorSummary"))
                .font(.headline)
            Text(mapping?.userMessage ?? L10n.string("Unknown initialization error"))
            Text(L10n.format("路径：%@", repoPath))
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
            DisclosureGroup(L10n.string("Show details"), isExpanded: $isDetailsExpanded) {
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
            Label(L10n.string("Preparing repository diagnostics..."), systemImage: "arrow.clockwise")
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
            Label(L10n.string("Diagnostics collected"), systemImage: "doc.badge.gearshape")
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
                Label(L10n.string("Diagnostics could not be collected"), systemImage: "exclamationmark.triangle")
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
            HoverableGhostButton(
                action: onQuit,
                icon: nil,
                title: L10n.string("onboarding.failed.quit")
            )

            HoverableGhostButton(
                action: onChangePath,
                icon: .folder,
                title: L10n.string("onboarding.failed.changeLocation")
            )

            Spacer()

            if canRetry {
                HoverableCapsuleButton(
                    action: onRetry,
                    title: L10n.string("onboarding.failed.retry"),
                    isDisabled: false,
                    accent: AreaMatrixTheme.Colors.coral
                )
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var isActionInFlight: Bool {
        if case .collecting = diagnostics {
            return true
        }
        return false
    }
}

private struct HoverableGhostButton: View {
    let action: () -> Void
    let icon: AreaMatrixLucideIcon.IconName?
    let title: String
    @Environment(\.areaMatrixInteractionFeedback) private var interactionFeedback
    @State private var isHovered = false

    var body: some View {
        AreaMatrixGhostButton(isHovered: isHovered, action: action) {
            HStack(spacing: 6) {
                if let icon {
                    AreaMatrixLucideIcon(name: icon, lineWidth: 2)
                        .frame(width: 14, height: 14)
                }
                Text(title)
            }
        }
        .onHover { hovering in
            isHovered = hovering
            interactionFeedback.setPointingCursor(active: hovering)
        }
    }
}

private struct HoverableCapsuleButton: View {
    let action: () -> Void
    let title: String
    let isDisabled: Bool
    let accent: Color
    @Environment(\.areaMatrixInteractionFeedback) private var interactionFeedback
    @State private var isHovered = false

    var body: some View {
        AreaMatrixCapsuleButton(accent: accent, isHovered: isHovered, action: action) {
            Text(title)
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        .onHover { hovering in
            if !isDisabled {
                isHovered = hovering
                interactionFeedback.setPointingCursor(active: hovering)
            }
        }
    }
}
