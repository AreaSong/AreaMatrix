import AppKit
import SwiftUI

@main
struct AreaMatrixApp: App {
    var body: some Scene {
        WindowGroup {
            MainWindow()
        }
        .windowResizability(.contentMinSize)
    }
}

struct MainRepoErrorView: View {
    let repoPath: String
    let mapping: CoreErrorMappingSnapshot?
    let validation: RepoPathValidationSnapshot?
    let isRetrying: Bool
    let retryErrorMapping: CoreErrorMappingSnapshot?
    let externalRemoval: MainRepoExternalRemovalState
    let onRetry: () -> Void
    let onConfirmExternalRemoval: () -> Void
    let onChooseAnotherFolder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            repositoryDetails
            actionRow
        }
        .frame(maxWidth: 620, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(48)
        .accessibilityElement(children: .contain)
    }

    init(
        repoPath: String,
        mapping: CoreErrorMappingSnapshot?,
        validation: RepoPathValidationSnapshot? = nil,
        isRetrying: Bool = false,
        retryErrorMapping: CoreErrorMappingSnapshot? = nil,
        externalRemoval: MainRepoExternalRemovalState = .unavailable,
        onRetry: @escaping () -> Void = {},
        onConfirmExternalRemoval: @escaping () -> Void = {},
        onChooseAnotherFolder: @escaping () -> Void
    ) {
        self.repoPath = repoPath
        self.mapping = mapping
        self.validation = validation
        self.isRetrying = isRetrying
        self.retryErrorMapping = retryErrorMapping
        self.externalRemoval = externalRemoval
        self.onRetry = onRetry
        self.onConfirmExternalRemoval = onConfirmExternalRemoval
        self.onChooseAnotherFolder = onChooseAnotherFolder
    }

    private var activeMapping: CoreErrorMappingSnapshot? {
        retryErrorMapping ?? mapping
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Repository could not be opened", systemImage: "exclamationmark.triangle")
                .font(.title.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text(activeMapping?.userMessage ?? "AreaMatrix could not open the selected repository.")
                .font(.body)
                .foregroundStyle(.secondary)
            Text("This error does not mean your files were deleted.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var repositoryDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Repository")
                .font(.headline)
            Text(repoPath)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(3)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            if let activeMapping {
                Text("Error: \(activeMapping.kind.rawValue)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Action: \(activeMapping.suggestedAction)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let validation {
                Text("Last validation: initialized=\(validation.isInitialized ? "yes" : "no")")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            externalRemovalStatus
        }
    }

    @ViewBuilder
    private var externalRemovalStatus: some View {
        switch externalRemoval {
        case .idle(let path):
            Text("External removal candidate: \(path)")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .syncing(let path):
            Text("Syncing external removal: \(path)")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .synced(let result):
            Text("External removals synced: \(result.detectedDeletes)")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .failed(let mapping):
            Text("External removal sync failed: \(mapping.userMessage)")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .unavailable:
            EmptyView()
        }
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button(isRetrying ? "Retrying..." : "Retry", action: onRetry)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isRetrying)
            if case .idle = externalRemoval {
                Button("Confirm external removal", action: onConfirmExternalRemoval)
                    .disabled(isRetrying)
            }
            Button("Choose another repository", action: onChooseAnotherFolder)
                .disabled(isRetrying)
            if isRetrying {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Retrying repository validation")
            }
        }
    }
}

struct DBRepairConfirmView: View {
    let repoPath: String
    let scanSession: ScanSessionSnapshot?
    let mapping: CoreErrorMappingSnapshot?
    let onResume: () -> Void
    let onCleanUpAndRetry: () -> Void
    let onChooseAnotherFolder: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Repository metadata needs repair", systemImage: "wrench.and.screwdriver")
        } description: {
            Text(mapping?.userMessage ?? "AreaMatrix found incomplete or damaged .areamatrix metadata.")
            Text(
                "Repair only affects .areamatrix/ metadata; user files are not moved, renamed, deleted, or overwritten."
            )
            if let scanSession {
                Text("Last scan: \(scanSession.status.rawValue), inserted \(scanSession.inserted).")
            }
            Text(repoPath)
        } actions: {
            if scanSession != nil {
                Button("Resume", action: onResume)
                    .keyboardShortcut(.defaultAction)
                Button("Clean up and retry", action: onCleanUpAndRetry)
            }
            Button("Choose another folder", action: onChooseAnotherFolder)
        }
    }
}

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
        ".areamatrix/generated/", ".areamatrix/staging/",
    ]

    private let adoptItems = [
        "创建 .areamatrix/ 内部目录",
        "创建 .areamatrix/ignore.yaml",
        "创建本地索引数据库",
        "扫描现有文件和文件夹",
        "将已有文件标记为 adopted / indexed",
        "生成 .areamatrix/generated/root.md",
    ]

    private let safetyItems = [
        "不移动已有文件",
        "不重命名已有文件",
        "不删除已有文件",
        "不覆盖已有 README.md",
        "不修改已有项目目录结构",
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
        .padding(.horizontal, 72)
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .confirmationDialog("退出设置？", isPresented: $isCancelConfirmationPresented) {
            Button("Quit", role: .destructive, action: onCancelSetup)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("AreaMatrix 不会写入资料库，下次启动可重新选择。")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isCreateMode ? "将创建新的 AreaMatrix 资料库" : "将接管已有目录")
                .font(.system(size: 34, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text("确认后才会开始写入 .areamatrix/ 元数据。")
                .font(.title3)
        }
    }

    private var pathBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("资料库路径")
                .font(.headline)
            Text(draft.validation.repoPath)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(3)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var planSection: some View {
        InitPlanList(title: isCreateMode ? "将创建" : "将执行", items: isCreateMode ? createItems : adoptItems)
    }

    private var safetySection: some View {
        InitPlanList(title: "不会执行", items: safetyItems, iconName: "checkmark.shield")
    }

    @ViewBuilder
    private var confirmationIssueSection: some View {
        if let issue = ConfirmInitStepRules.blockingMessage(for: draft) {
            Label(issue, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.red)
                .padding(12)
                .frame(maxWidth: 680, alignment: .leading)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var iCloudWarning: some View {
        if draft.validation.isICloudPath {
            Label(
                "该路径位于 iCloud 管理范围内，请确认文件已在本机可用。",
                systemImage: "icloud"
            )
                .font(.callout)
                .foregroundStyle(.orange)
        }
    }

    private var footer: some View {
        HStack {
            if footerActions.contains(.back) {
                Button("Back", action: onBack)
            }
            if footerActions.contains(.cancelSetup) {
                Button("Cancel Setup") {
                    isCancelConfirmationPresented = true
                }
            }
            if footerActions.contains(.changePath) {
                Button("Change Path", action: onChangePath)
            }
            Spacer()
            if footerActions.contains(.primary) {
                Button(isCreateMode ? "Create Repository" : "Adopt Folder", action: primaryAction)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
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
        }
    }
}
