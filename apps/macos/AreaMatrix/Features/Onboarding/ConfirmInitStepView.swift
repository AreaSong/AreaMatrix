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

    private let adoptItems = [
        "创建 .areamatrix/ 内部目录",
        "创建 .areamatrix/ignore.yaml",
        "创建本地索引数据库",
        "扫描现有文件和文件夹",
        "将已有文件标记为 adopted / indexed",
        "生成 .areamatrix/generated/root.md"
    ]

    private let safetyItems = [
        "不移动已有文件",
        "不重命名已有文件",
        "不删除已有文件",
        "不覆盖已有 README.md",
        "不修改已有项目目录结构"
    ]

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
        .confirmationDialog(String(localized: "onboarding.confirm.quitSetup"), isPresented: $isCancelConfirmationPresented) {
            Button(String(localized: "onboarding.confirm.quit"), role: .destructive, action: onCancelSetup)
            Button(String(localized: "settings.action.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "onboarding.confirm.cancelSetupMessage"))
        }
    }

    private var header: some View {
        AreaMatrixStepHeader(
            systemImage: isCreateMode ? "plus.rectangle.on.folder" : "folder.badge.plus",
            tint: AreaMatrixTheme.Colors.tealBright,
            title: isCreateMode
                ? String(localized: "onboarding.confirm.createTitle")
                : String(localized: "onboarding.confirm.adoptTitle"),
            subtitle: String(localized: "onboarding.confirm.subtitle")
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pathBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "onboarding.confirm.repoPath"))
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
                ? String(localized: "onboarding.confirm.willCreate")
                : String(localized: "onboarding.confirm.willExecute"),
            items: isCreateMode ? createItems : adoptItems
        )
    }

    private var safetySection: some View {
        InitPlanList(title: String(localized: "onboarding.confirm.willNotExecute"), items: safetyItems, iconName: "checkmark.shield")
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
                String(localized: "onboarding.confirm.icloudWarning"),
                systemImage: "icloud"
            )
            .font(.callout)
            .foregroundStyle(.orange)
        }
    }

    private var footer: some View {
        HStack {
            if footerActions.contains(.back) {
                Button(String(localized: "onboarding.confirm.back"), action: onBack)
                    .buttonStyle(AreaMatrixSecondaryButtonStyle())
            }
            if footerActions.contains(.cancelSetup) {
                Button(String(localized: "onboarding.confirm.cancelSetup")) {
                    isCancelConfirmationPresented = true
                }
                .buttonStyle(AreaMatrixSecondaryButtonStyle())
            }
            if footerActions.contains(.changePath) {
                Button(String(localized: "onboarding.confirm.changePath"), action: onChangePath)
                    .buttonStyle(AreaMatrixSecondaryButtonStyle())
            }
            Spacer()
            if footerActions.contains(.primary) {
                Button(
                    isCreateMode
                        ? String(localized: "onboarding.confirm.createRepository")
                        : String(localized: "onboarding.confirm.adoptFolder"),
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
            return "路径状态已变化，请返回校验页。"
        }
        guard validation.isReadable, validation.isWritable else {
            return "路径权限已变化，请返回校验页。"
        }
        guard !validation.isInsideAreaMatrix else {
            return "请选择资料库根目录，而不是 .areamatrix 内部目录。"
        }
        guard !validation.isInitialized else {
            return "该路径已经是 AreaMatrix 资料库，请返回校验页。"
        }
        guard !validation.hasUnfinishedScanSession else {
            return "该资料库存在未完成的扫描记录，请返回修复流程。"
        }
        guard !validation.hasMissingEnvironmentChecks else {
            return "路径环境检查缺失，请返回校验页。"
        }
        guard validation.recommendedMode == draft.mode else {
            return "路径初始化模式已变化，请返回校验页。"
        }

        switch draft.mode {
        case .createEmpty:
            return validation.isEmpty ? nil : "路径已不是空目录，请返回校验页。"
        case .adoptExisting:
            return validation.isEmpty ? "路径已变为空目录，请返回校验页。" : nil
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
