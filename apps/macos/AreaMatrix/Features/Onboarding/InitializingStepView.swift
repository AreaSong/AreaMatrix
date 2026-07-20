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
    }

    private var header: some View {
        AreaMatrixStepHeader(
            title: isCreateMode ? "正在创建资料库" : "正在接管已有目录",
            subtitle: detailText
        ) {
            ProgressView()
                .controlSize(.large)
                .accessibilityLabel(accessibilityProgressLabel)
        }
    }

    private var pathBox: some View {
        AreaMatrixPathBox(path: draft.validation.repoPath)
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("当前进度")
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
                Label("启动恢复已执行", systemImage: "arrow.clockwise.circle")
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
                Label("接管扫描 warning", systemImage: "exclamationmark.triangle")
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
        Text("AreaMatrix 不会移动、重命名、删除或覆盖用户原文件。")
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
                Text("正在暂停...")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 8)
            }

            Button(action: onCancel) {
                Text("取消")
                    .font(.body.weight(.medium))
            }
            .controlSize(.large)
            .disabled(isCancellationRequested)
        }
        .frame(maxWidth: 440)
        .padding(.top, 16)
    }

    private var statusText: String {
        if isCancellationRequested {
            return "正在等待 Core 到达安全点"
        }

        if isCreateMode {
            return "正在初始化本地索引"
        }

        guard let scanSession else {
            return "正在创建内部元数据并等待接管扫描状态"
        }

        switch scanSession.status {
        case .running:
            return "正在扫描现有文件"
        case .completed:
            return "接管扫描已完成"
        case .paused:
            return "接管扫描已暂停"
        case .failed:
            return "接管扫描失败"
        case .interrupted:
            return "接管扫描已中断"
        }
    }

    private var detailText: String {
        isCreateMode ? "Core 正在创建空资料库所需的 .areamatrix/ 元数据。"
            : "Core 正在接管目录；已有文件只会被扫描和索引。"
    }

    private var scanCountText: String {
        guard !isCreateMode else {
            return "已扫描：不适用"
        }

        guard let scanSession else {
            return "已扫描：等待 Core 回报"
        }

        return """
        已扫描：\(scanSession.processedCount) 个文件（新增 \(scanSession.inserted)，\
        更新 \(scanSession.updated)，跳过 \(scanSession.skipped)）
        """
    }

    private var currentFileText: String {
        guard !isCreateMode else {
            return "当前文件：不适用"
        }

        return "当前文件：\(scanSession?.lastPath ?? "等待 Core 回报")"
    }

    private var accessibilityProgressLabel: String {
        "\(statusText)。\(scanCountText)。\(currentFileText)。"
    }

    private var stepRows: [InitializingStepRow] {
        if isCreateMode {
            return [
                .pending("创建 .areamatrix/ 内部目录"),
                .pending("初始化 index.db"),
                .pending("创建默认分类与 ignore.yaml"),
                .pending("写入 .areamatrix/generated/root.md")
            ]
        }

        return [
            .completed("创建 .areamatrix/ 内部目录", when: scanSession != nil),
            .completed("初始化 index.db", when: scanSession != nil),
            .running("扫描现有文件", when: scanSession?.status == .running),
            .completed("写入索引", when: scanSession?.hasIndexedFiles == true),
            .completed("生成资料库概览", when: scanSession?.status == .completed)
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
        """
        已清理临时文件：\(cleanedStagingFiles)；\
        已回滚 staging 记录：\(revertedStagingDbRows)
        """
    }
}
