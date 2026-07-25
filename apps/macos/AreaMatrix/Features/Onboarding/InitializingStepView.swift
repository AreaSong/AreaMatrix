import SwiftUI

struct InitializingStepView: View {
    @EnvironmentObject private var localizer: AppLocalizer
    let draft: RepositoryInitializationDraft
    let scanSession: ScanSessionSnapshot?
    let recoveryReport: RecoveryReportSnapshot?
    let progressWarning: LocalizedMessage?
    let isCancellationRequested: Bool
    let onCancel: () -> Void

    private var isCreateMode: Bool {
        draft.mode == .createEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            header

            VStack(alignment: .leading, spacing: 20) {
                pathBox
                recoverySection
                progressSection
                stepList
                warningSection
                safetyText
            }
            
            Spacer()
            footer
        }
        .frame(maxWidth: 580)
        .padding(.horizontal, 48)
        .padding(.vertical, 32)
        .areaMatrixOnboardingPanel()
        .areaMatrixPageContentEntrance(delay: AreaMatrixMotionTokens.EntranceDelay.body)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                AreaMatrixLucideIcon(name: isCreateMode ? .filePlus2 : .folderOpen, lineWidth: 2)
                    .frame(width: 28, height: 28)
                    .foregroundStyle(AreaMatrixTheme.Colors.teal)
                    .background(
                        Circle()
                            .fill(AreaMatrixTheme.Colors.teal.opacity(0.1))
                            .frame(width: 48, height: 48)
                    )
                Text("SYSTEM INITALIZATION")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundStyle(AreaMatrixTheme.Colors.teal)
                    .tracking(6)
            }
            .padding(.bottom, 8)
            
            HStack(alignment: .center) {
                Text(isCreateMode ? L10n.string("onboarding.initializing.createTitle") : L10n.string("onboarding.initializing.adoptTitle"))
                    .font(.system(size: 42, weight: .heavy))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                
                Spacer()
                
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(accessibilityProgressLabel)
            }
            
            Text(detailText)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 20)
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
                ForEach(Array(stepRows.enumerated()), id: \.element.title) { index, row in
                    HStack(spacing: 10) {
                        AreaMatrixLucideIcon(name: row.iconName, lineWidth: 2)
                            .frame(width: 16, height: 16)
                            .foregroundStyle(row.tint)
                        
                        Text(row.title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(row.tint == .secondary ? .secondary : .primary)
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .animation(
                        .spring(response: 0.4, dampingFraction: 0.75).delay(Double(index) * 0.04),
                        value: stepRows.map(\.title)
                    )
                }
            }
            .accessibilityElement(children: .combine)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
                    )
            )
        }
    }

    @ViewBuilder
    private var warningSection: some View {
        if let progressWarning {
            Label(localizer.resolve(progressWarning), systemImage: "exclamationmark.triangle")
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
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.string("onboarding.initializing.pausing"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.trailing, 8)
            }

            HoverableGhostButton(
                action: onCancel,
                icon: .xCircle,
                title: L10n.string("onboarding.initializing.cancel")
            )
            .disabled(isCancellationRequested)
            .opacity(isCancellationRequested ? 0.5 : 1)
        }
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

private struct HoverableGhostButton: View {
    let action: () -> Void
    let icon: AreaMatrixLucideIcon.IconName?
    let title: String
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
            AppPlatformServices.interactionFeedback.setPointingCursor(active: hovering)
        }
    }
}
