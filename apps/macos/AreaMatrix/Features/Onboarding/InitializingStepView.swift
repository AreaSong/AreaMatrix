import SwiftUI

struct InitializingStepView: View {
    let draft: RepositoryInitializationDraft
    let scanSession: ScanSessionSnapshot?
    let recoveryReport: RecoveryReportSnapshot?
    let progressWarning: String?
    let isCancellationRequested: Bool
    let onCancel: () -> Void

    private var isCreateMode: Bool {
        draft.mode == .createEmpty
    }

    var body: some View {
        VStack(alignment: .center, spacing: 28) {
            header

            VStack(spacing: 20) {
                pathBox
                recoverySection
                progressSection
                stepList
                warningSection
                safetyText
            }
            .frame(maxWidth: 440)

            footer
        }
        .areaMatrixOnboardingPanel()
        .areaMatrixPageContentEntrance(delay: AreaMatrixMotionTokens.EntranceDelay.body)
    }

    private var header: some View {
        AreaMatrixStepHeader(
            title: isCreateMode
                ? L10n.string("onboarding.initializing.createTitle")
                : L10n.string("onboarding.initializing.adoptTitle"),
            subtitle: detailText
        ) {
            ProgressView()
                .controlSize(.large)
                .tint(AreaMatrixTheme.Colors.tealBright)
                .accessibilityLabel(accessibilityProgressLabel)
        }
    }

    private var pathBox: some View {
        AreaMatrixPathBox(path: draft.validation.repoPath)
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("onboarding.initializing.progress"))
                .font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                Text(statusText)
                Text(scanCountText)
                Text(currentFileText)
            }
            .font(.callout)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .areaMatrixGlassCard()
        }
    }

    @ViewBuilder
    private var recoverySection: some View {
        if let recoveryReport, recoveryReport.hasVisibleDetails {
            VStack(alignment: .leading, spacing: 8) {
                Label(L10n.string("onboarding.initializing.recoveryExecuted"), systemImage: "arrow.clockwise.circle")
                    .font(.headline)
                Text(recoveryReport.summaryText)
                    .font(.callout)
                ForEach(recoveryReport.warnings.prefix(3), id: \.self) { warning in
                    Text(warning)
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .areaMatrixGlassCard()
            .accessibilityElement(children: .combine)
        }
    }

    private var stepList: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(stepRows, id: \.title) { row in
                    Label(row.title, systemImage: row.systemImage)
                        .font(.callout)
                        .foregroundStyle(row.tint)
                }
            }
            .accessibilityElement(children: .combine)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .areaMatrixGlassCard()
        }
    }

    @ViewBuilder
    private var warningSection: some View {
        if let progressWarning {
            Label(progressWarning, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        if let scanSession, !scanSession.errors.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label(L10n.string("onboarding.initializing.scanWarning"), systemImage: "exclamationmark.triangle")
                    .font(.callout.weight(.semibold))
                ForEach(scanSession.errors.prefix(3), id: \.self) { error in
                    Text(error)
                        .font(.callout)
                }
            }
            .foregroundStyle(.orange)
            .frame(maxWidth: 680, alignment: .leading)
        }
    }

    private var safetyText: some View {
        Text(L10n.string("onboarding.initializing.safety"))
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var footer: some View {
        HStack {
            Spacer()

            if isCancellationRequested {
                ProgressView()
                    .controlSize(.small)
                Text(L10n.string("onboarding.initializing.pausing"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 8)
            }

            Button(action: onCancel) {
                Text(L10n.string("onboarding.initializing.cancel"))
                    .font(.body.weight(.medium))
            }
            .buttonStyle(AreaMatrixSecondaryButtonStyle())
            .controlSize(.large)
            .disabled(isCancellationRequested)
        }
        .frame(maxWidth: 440)
        .padding(.top, 16)
    }

    private var statusText: String {
        if isCancellationRequested {
            return L10n.string("onboarding.initializing.waitingForSafePoint")
        }

        if isCreateMode {
            return L10n.string("onboarding.initializing.creatingIndex")
        }

        guard let scanSession else {
            return L10n.string("onboarding.initializing.waitingForAdoptScan")
        }

        switch scanSession.status {
        case .running:
            return L10n.string("onboarding.initializing.scanningFiles")
        case .completed:
            return L10n.string("onboarding.initializing.scanCompleted")
        case .paused:
            return L10n.string("onboarding.initializing.scanPaused")
        case .failed:
            return L10n.string("onboarding.initializing.scanFailed")
        case .interrupted:
            return L10n.string("onboarding.initializing.scanInterrupted")
        }
    }

    private var detailText: String {
        isCreateMode ? L10n.string("onboarding.initializing.createDetail")
            : L10n.string("onboarding.initializing.adoptDetail")
    }

    private var scanCountText: String {
        guard !isCreateMode else {
            return L10n.string("onboarding.initializing.scanCountNotApplicable")
        }

        guard let scanSession else {
            return L10n.string("onboarding.initializing.scanCountWaiting")
        }

        return L10n.format(
            "onboarding.initializing.scanCount",
            scanSession.processedCount,
            scanSession.inserted,
            scanSession.updated,
            scanSession.skipped
        )
    }

    private var currentFileText: String {
        guard !isCreateMode else {
            return L10n.string("onboarding.initializing.currentFileNotApplicable")
        }

        let path = scanSession?.lastPath ?? L10n.string("onboarding.initializing.waitingForCore")
        return L10n.format("onboarding.initializing.currentFile", path)
    }

    private var accessibilityProgressLabel: String {
        L10n.format("onboarding.initializing.accessibility-progress", statusText, scanCountText, currentFileText)
    }

    private var stepRows: [InitializingStepRow] {
        if isCreateMode {
            return [
                .pending(L10n.string("onboarding.initializing.step.createMetadata")),
                .pending(L10n.string("onboarding.initializing.step.initializeIndex")),
                .pending(L10n.string("onboarding.initializing.step.createDefaults")),
                .pending(L10n.string("onboarding.initializing.step.writeOverview"))
            ]
        }

        return [
            .completed(L10n.string("onboarding.initializing.step.createMetadata"), when: scanSession != nil),
            .completed(L10n.string("onboarding.initializing.step.initializeIndex"), when: scanSession != nil),
            .running(L10n.string("onboarding.initializing.step.scanFiles"), when: scanSession?.status == .running),
            .completed(
                L10n.string("onboarding.initializing.step.writeIndex"),
                when: scanSession?.hasIndexedFiles == true
            ),
            .completed(
                L10n.string("onboarding.initializing.step.generateOverview"),
                when: scanSession?.status == .completed
            )
        ]
    }
}

private extension ScanSessionSnapshot {
    var processedCount: Int64 {
        inserted + updated + skipped
    }

    var hasIndexedFiles: Bool {
        processedCount > 0 || status == .completed
    }
}

private extension RecoveryReportSnapshot {
    var summaryText: String {
        L10n.format("onboarding.recovery.cleanupSummary", cleanedStagingFiles, revertedStagingDbRows)
    }
}
