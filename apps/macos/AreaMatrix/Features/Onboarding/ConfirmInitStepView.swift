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
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    pathBox
                    planSection
                    confirmationIssueSection
                    safetySection
                    iCloudWarning
                }
                .frame(maxWidth: 680, alignment: .leading)
            }
            footer
        }
        .padding(40)
        .areaMatrixGlassContentPanel(width: 720, padding: 0)
        .areaMatrixPageContentEntrance(delay: AreaMatrixMotionTokens.EntranceDelay.body)
        .confirmationDialog(L10n.string("onboarding.confirm.quitSetup"), isPresented: $isCancelConfirmationPresented) {
            Button(L10n.string("onboarding.confirm.quit"), role: .destructive, action: onCancelSetup)
            Button(L10n.string("settings.action.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.string("onboarding.confirm.cancelSetupMessage"))
        }
    }

    private var header: some View {
        AreaMatrixStepHeader(
            systemImage: isCreateMode ? "plus.rectangle.on.folder" : "folder.badge.plus",
            tint: AreaMatrixTheme.Colors.tealBright,
            title: isCreateMode
                ? L10n.string("onboarding.confirm.createTitle")
                : L10n.string("onboarding.confirm.adoptTitle"),
            subtitle: L10n.string("onboarding.confirm.subtitle")
        )
        .frame(maxWidth: .infinity, alignment: .leading)
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
            items: isCreateMode ? createItems : adoptItems
        )
    }

    private var safetySection: some View {
        InitPlanList(
            title: L10n.string("onboarding.confirm.willNotExecute"),
            items: safetyItems,
            iconName: "checkmark.shield"
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
                Button(L10n.string("onboarding.confirm.back"), action: onBack)
                    .buttonStyle(AreaMatrixSecondaryButtonStyle())
            }
            if footerActions.contains(.cancelSetup) {
                Button(L10n.string("onboarding.confirm.cancelSetup")) {
                    isCancelConfirmationPresented = true
                }
                .buttonStyle(AreaMatrixSecondaryButtonStyle())
            }
            if footerActions.contains(.changePath) {
                Button(L10n.string("onboarding.confirm.changePath"), action: onChangePath)
                    .buttonStyle(AreaMatrixSecondaryButtonStyle())
            }
            Spacer()
            if footerActions.contains(.primary) {
                Button(
                    isCreateMode
                        ? L10n.string("onboarding.confirm.createRepository")
                        : L10n.string("onboarding.confirm.adoptFolder"),
                    action: primaryAction
                )
                .keyboardShortcut(.defaultAction)
                .buttonStyle(AreaMatrixPrimaryButtonStyle())
                .disabled(!canRunPrimaryAction)
            }
        }
        .frame(maxWidth: 680)
        .padding(.top, 18)
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
    var iconName = "plus.circle"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: iconName)
                .font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { item in
                    Text("• \(item)")
                        .font(.callout)
                        .accessibilityLabel(item)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .areaMatrixGlassCard(cornerRadius: 10)
        }
    }
}
