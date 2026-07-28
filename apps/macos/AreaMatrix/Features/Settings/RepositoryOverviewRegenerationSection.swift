import SwiftUI

struct RepositoryOverviewRegenerationSection: View {
    @EnvironmentObject private var localizer: AppLocalizer
    @ObservedObject var model: RepositoryOverviewRegenerationModel

    var body: some View {
        RepositorySettingsSection(title: L10n.string("settings.repository.overview.section")) {
            statusContent
            phaseContent
            sharedOperationContent
        }
        .accessibilityIdentifier("repository-settings-overview-regeneration")
    }

    @ViewBuilder
    private var statusContent: some View {
        if let status = model.languageStatus {
            LabeledContent(
                L10n.string("settings.repository.overview.languageStatus"),
                value: stateLabel(status.state)
            )
            LabeledContent(L10n.string("settings.repository.overview.targetLocale")) {
                Text(localeLabel(status.contentLocale))
            }
            if !status.reasons.isEmpty {
                Text(status.reasons.map(reasonLabel).joined(separator: ", "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if status.state != .synchronized, model.sharedOperation == nil {
                Button(L10n.string("settings.repository.overview.prepare")) {
                    Task { await model.prepare() }
                }
                .disabled(model.phase.isBusy)
            }
        } else if model.phase == .loading {
            SettingsProgressBanner(title: L10n.string("settings.repository.overview.checking"))
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch model.phase {
        case .idle, .loading:
            EmptyView()
        case let .preflight(plan):
            preflight(plan)
        case .starting:
            SettingsProgressBanner(title: L10n.string("settings.repository.overview.staging"))
        case .committing:
            SettingsProgressBanner(title: L10n.string("settings.repository.overview.committing"))
        case .canceling:
            SettingsProgressBanner(title: L10n.string("settings.repository.overview.canceling"))
        case .recovering:
            SettingsProgressBanner(title: L10n.string("settings.repository.overview.recovering"))
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

    private func preflight(_ plan: CoreOverviewRegenerationPlanSnapshot) -> some View {
        SettingsStatusBanner(
            title: L10n.string("settings.repository.overview.preflightTitle"),
            systemImage: "doc.text.magnifyingglass",
            tint: .orange
        ) {
            LabeledContent(L10n.string("settings.repository.overview.targetLocale")) {
                Text(localeLabel(plan.contentLocale))
            }
            Text(L10n.format(
                "settings.repository.overview.preflightCounts",
                plan.createCount,
                plan.replaceCount,
                plan.deleteCount
            ))
            Text(plan.includesRootAreaMatrixFile
                ? L10n.string("settings.repository.overview.includesManagedRoot")
                : L10n.string("settings.repository.overview.excludesManagedRoot"))
            Text(L10n.string("settings.repository.overview.exclusions"))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button(L10n.string("Cancel"), role: .cancel, action: model.cancelPreflight)
                Button(L10n.string("settings.repository.overview.stageConfirmed")) {
                    Task { await model.stageConfirmedPlan() }
                }
            }
        }
    }

    @ViewBuilder
    private var sharedOperationContent: some View {
        if let operation = model.sharedOperation {
            let session = operation.session
            SettingsStatusBanner(
                title: sessionTitle(session.status),
                systemImage: sessionIcon(session.status),
                tint: sessionTint(session.status)
            ) {
                Text(L10n.format(
                    "settings.repository.overview.progress",
                    session.appliedCount,
                    session.targetCount
                ))
                .font(.callout)

                if session.status == .readyToCommit {
                    if model.canInteractWithSharedOperation {
                        HStack(spacing: 10) {
                            Button(L10n.string("Cancel"), role: .cancel) {
                                Task { await model.cancel() }
                            }
                            .disabled(!session.cancellationAllowed || model.phase.isBusy)
                            Button(L10n.string("settings.repository.overview.commit")) {
                                Task { await model.commit() }
                            }
                            .disabled(model.phase.isBusy)
                        }
                    } else {
                        Text(L10n.string("settings.repository.overview.observer"))
                            .foregroundStyle(.secondary)
                    }
                }

                if session.status == .rollbackRequired {
                    if model.canInteractWithSharedOperation {
                        Button(L10n.string("settings.repository.overview.recoverSafely")) {
                            Task { await model.recoverSafely() }
                        }
                        .disabled(model.phase.isBusy)
                    } else {
                        Text(L10n.string("settings.repository.overview.observer"))
                            .foregroundStyle(.secondary)
                    }
                }

                if [.completed, .rolledBack, .failed, .canceled].contains(session.status) {
                    Button(L10n.string("Dismiss"), action: model.dismissTerminalOperation)
                }
            }
        }
    }

    private func stateLabel(_ state: CoreOverviewLanguageStateSnapshot) -> String {
        switch state {
        case .notGenerated: L10n.string("settings.repository.overview.state.notGenerated")
        case .synchronized: L10n.string("settings.repository.overview.state.synchronized")
        case .needsRegeneration: L10n.string("settings.repository.overview.state.needsRegeneration")
        case .mixed: L10n.string("settings.repository.overview.state.mixed")
        case .unknown: L10n.string("settings.repository.overview.state.unknown")
        }
    }

    private func reasonLabel(_ reason: CoreOverviewRegenerationReasonSnapshot) -> String {
        switch reason {
        case .localeMismatch: L10n.string("settings.repository.overview.reason.localeMismatch")
        case .formatMismatch: L10n.string("settings.repository.overview.reason.formatMismatch")
        case .missingTargets: L10n.string("settings.repository.overview.reason.missingTargets")
        case .obsoleteTargets: L10n.string("settings.repository.overview.reason.obsoleteTargets")
        }
    }

    private func localeLabel(_ locale: String) -> String {
        locale == "zh-Hans"
            ? L10n.string("settings.language.simplifiedChinese")
            : L10n.string("settings.language.english")
    }

    private func sessionTitle(_ status: CoreOverviewRegenerationStatusSnapshot) -> String {
        switch status {
        case .running, .staging: L10n.string("settings.repository.overview.staging")
        case .readyToCommit: L10n.string("settings.repository.overview.ready")
        case .committing: L10n.string("settings.repository.overview.committing")
        case .completed: L10n.string("settings.repository.overview.completed")
        case .rollbackRequired: L10n.string("settings.repository.overview.recoveryRequired")
        case .rolledBack: L10n.string("settings.repository.overview.rolledBack")
        case .failed: L10n.string("settings.repository.overview.failed")
        case .canceled: L10n.string("settings.repository.overview.canceled")
        }
    }

    private func sessionIcon(_ status: CoreOverviewRegenerationStatusSnapshot) -> String {
        switch status {
        case .completed: "checkmark.circle"
        case .rollbackRequired, .failed: "exclamationmark.triangle"
        case .rolledBack, .canceled: "arrow.uturn.backward.circle"
        default: "arrow.triangle.2.circlepath"
        }
    }

    private func sessionTint(_ status: CoreOverviewRegenerationStatusSnapshot) -> Color {
        switch status {
        case .completed: .green
        case .rollbackRequired, .failed: .red
        case .rolledBack, .canceled: .orange
        default: .accentColor
        }
    }
}
