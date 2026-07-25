import SwiftUI

struct ConfirmInitStepView: View {
    let draft: RepositoryInitializationDraft
    let onBack: () -> Void
    let onChangePath: () -> Void
    let onCreateEmpty: () -> Void
    let onAdoptExisting: () -> Void
    let onCancelSetup: () -> Void

    @State private var isCancelConfirmationPresented = false

    private let createItems = [
        "docs/", "code/", "design/", "finance/", "media/", "inbox/",
        ".areamatrix/index.db", ".areamatrix/ignore.yaml",
        ".areamatrix/generated/", ".areamatrix/staging/"
    ]

    private var adoptItems: [String] {
        [
            L10n.string("onboarding.confirm.adopt.createMetadata"),
            L10n.string("onboarding.confirm.adopt.createIgnoreFile"),
            L10n.string("onboarding.confirm.adopt.createIndex"),
            L10n.string("onboarding.confirm.adopt.scanFiles"),
            L10n.string("onboarding.confirm.adopt.markIndexed"),
            L10n.string("onboarding.confirm.adopt.generateOverview")
        ]
    }

    private var safetyItems: [String] {
        [
            L10n.string("onboarding.confirm.safety.noMove"),
            L10n.string("onboarding.confirm.safety.noRename"),
            L10n.string("onboarding.confirm.safety.noDelete"),
            L10n.string("onboarding.confirm.safety.noReadmeOverwrite"),
            L10n.string("onboarding.confirm.safety.noStructureChange")
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            header
            
            VStack(alignment: .leading, spacing: 24) {
                pathBox
                planSection
                confirmationIssueSection
                safetySection
                iCloudWarning
            }
            .padding(.top, 10)
            
            Spacer()
            footer
        }
        .frame(maxWidth: 580)
        .padding(.horizontal, 48)
        .padding(.vertical, 32)
        .areaMatrixOnboardingPanel()
        .areaMatrixPageContentEntrance(delay: AreaMatrixMotionTokens.EntranceDelay.body)
        .confirmationDialog(L10n.string("onboarding.confirm.quitSetup"), isPresented: $isCancelConfirmationPresented) {
            Button(L10n.string("onboarding.confirm.quit"), role: .destructive, action: onCancelSetup)
            Button(L10n.string("settings.action.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.string("onboarding.confirm.cancelSetupMessage"))
        }
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
                Text("INITIALIZATION")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundStyle(AreaMatrixTheme.Colors.teal)
                    .tracking(6)
            }
            .padding(.bottom, 8)
            
            Text(isCreateMode ? L10n.string("onboarding.confirm.createTitle") : L10n.string("onboarding.confirm.adoptTitle"))
                .font(.system(size: 42, weight: .heavy))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            
            Text(L10n.string("onboarding.confirm.subtitle"))
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 20)
    }

    private var pathBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("onboarding.confirm.repoPath"))
                .font(.headline)
            AreaMatrixPathBox(
                path: draft.validation.repoPath,
                style: .glass,
                lineLimit: 3,
                alignment: .leading
            )
        }
    }

    private var planSection: some View {
        InitPlanList(
            title: isCreateMode
                ? L10n.string("onboarding.confirm.willCreate")
                : L10n.string("onboarding.confirm.willExecute"),
            items: isCreateMode ? createItems : adoptItems,
            iconName: .checkCircle
        )
    }

    private var safetySection: some View {
        InitPlanList(
            title: L10n.string("onboarding.confirm.willNotExecute"),
            items: safetyItems,
            iconName: .shieldCheck,
            tint: .blue
        )
    }

    @ViewBuilder
    private var confirmationIssueSection: some View {
        if let issue = ConfirmInitStepRules.blockingMessage(for: draft) {
            TintedStatusBanner(tint: .red) {
                Label(issue, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            .frame(maxWidth: 680, alignment: .leading)
        }
    }

    @ViewBuilder
    private var iCloudWarning: some View {
        if draft.validation.isICloudPath {
            Label(
                L10n.string("onboarding.confirm.icloudWarning"),
                systemImage: "icloud"
            )
            .font(.callout)
            .foregroundStyle(.orange)
        }
    }

    private var footer: some View {
        HStack {
            if footerActions.contains(.back) {
                HoverableGhostButton(
                    action: onBack,
                    icon: .arrowLeft,
                    title: L10n.string("onboarding.confirm.back")
                )
            }
            if footerActions.contains(.cancelSetup) {
                HoverableGhostButton(
                    action: { isCancelConfirmationPresented = true },
                    icon: .xCircle,
                    title: L10n.string("onboarding.confirm.cancelSetup")
                )
            }
            if footerActions.contains(.changePath) {
                HoverableGhostButton(
                    action: onChangePath,
                    icon: .folder,
                    title: L10n.string("onboarding.confirm.changePath")
                )
            }
            Spacer()
            if footerActions.contains(.primary) {
                HoverableCapsuleButton(
                    action: primaryAction,
                    title: isCreateMode ? L10n.string("onboarding.confirm.createRepository") : L10n.string("onboarding.confirm.adoptFolder"),
                    isDisabled: !canRunPrimaryAction,
                    accent: AreaMatrixTheme.Colors.teal
                )
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var primaryAction: () -> Void {
        isCreateMode ? onCreateEmpty : onAdoptExisting
    }

    private var canRunPrimaryAction: Bool {
        ConfirmInitStepRules.canRunPrimaryAction(for: draft)
    }

    private var footerActions: [ConfirmInitFooterAction] {
        ConfirmInitStepRules.footerActions(for: draft)
    }

    private var isCreateMode: Bool {
        draft.mode == .createEmpty
    }
}

enum ConfirmInitFooterAction: Equatable {
    case back
    case cancelSetup
    case changePath
    case primary
}

enum ConfirmInitStepRules {
    static func footerActions(for draft: RepositoryInitializationDraft) -> [ConfirmInitFooterAction] {
        guard canRunPrimaryAction(for: draft) else {
            return [.back, .cancelSetup]
        }

        return [.back, .cancelSetup, .changePath, .primary]
    }

    static func canRunPrimaryAction(for draft: RepositoryInitializationDraft) -> Bool {
        blockingMessage(for: draft) == nil
    }

    static func canCreateEmpty(for draft: RepositoryInitializationDraft) -> Bool {
        draft.mode == .createEmpty &&
            draft.validation.recommendedMode == .createEmpty &&
            draft.validation.isEmpty &&
            !draft.validation.isInitialized
    }

    static func canAdoptExisting(for draft: RepositoryInitializationDraft) -> Bool {
        draft.mode == .adoptExisting &&
            draft.validation.recommendedMode == .adoptExisting &&
            !draft.validation.isEmpty &&
            !draft.validation.isInitialized
    }

    static func blockingMessage(for draft: RepositoryInitializationDraft) -> String? {
        let validation = draft.validation

        guard validation.exists, validation.isDirectory else {
            return L10n.string("onboarding.confirm.blocked.pathChanged")
        }
        guard validation.isReadable, validation.isWritable else {
            return L10n.string("onboarding.confirm.blocked.permissionsChanged")
        }
        guard !validation.isInsideAreaMatrix else {
            return L10n.string("onboarding.confirm.blocked.insideMetadata")
        }
        guard !validation.isInitialized else {
            return L10n.string("onboarding.confirm.blocked.alreadyInitialized")
        }
        guard !validation.hasUnfinishedScanSession else {
            return L10n.string("onboarding.confirm.blocked.unfinishedScan")
        }
        guard !validation.hasMissingEnvironmentChecks else {
            return L10n.string("onboarding.confirm.blocked.missingChecks")
        }
        guard validation.recommendedMode == draft.mode else {
            return L10n.string("onboarding.confirm.blocked.modeChanged")
        }

        switch draft.mode {
        case .createEmpty:
            return validation.isEmpty ? nil : L10n.string("onboarding.confirm.blocked.noLongerEmpty")
        case .adoptExisting:
            return validation.isEmpty ? L10n.string("onboarding.confirm.blocked.nowEmpty") : nil
        }
    }
}

private struct InitPlanList: View {
        let title: String
        let items: [String]
        var iconName: AreaMatrixLucideIcon.IconName = .checkCircle
        var tint: Color = AreaMatrixTheme.Colors.teal

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    AreaMatrixLucideIcon(name: iconName, lineWidth: 2)
                        .frame(width: 16, height: 16)
                        .foregroundStyle(tint)
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.element) { index, item in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(tint.opacity(0.8))
                            Text(item)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .transition(.move(edge: .leading).combined(with: .opacity))
                        .animation(
                            .spring(response: 0.4, dampingFraction: 0.75).delay(Double(index) * 0.04),
                            value: items
                        )
                    }
                }
                .padding(.leading, 8)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
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

    private struct HoverableCapsuleButton: View {
        let action: () -> Void
        let title: String
        let isDisabled: Bool
        let accent: Color
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
                    AppPlatformServices.interactionFeedback.setPointingCursor(active: hovering)
                }
            }
        }
    }
