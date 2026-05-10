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
        VStack(alignment: .leading, spacing: 22) {
            header
            pathBox
            recoverySection
            progressSection
            stepList
            warningSection
            safetyText
            footer
        }
        .padding(.horizontal, 72)
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(statusText)
                .controlSize(.large)
                .accessibilityLabel(accessibilityProgressLabel)
            Text(isCreateMode ? "正在创建资料库" : "正在接管已有目录")
                .font(.system(size: 34, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text(detailText)
                .font(.title3)
                .frame(maxWidth: 680, alignment: .leading)
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
                .frame(maxWidth: 680, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
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
            .padding(14)
            .frame(maxWidth: 680, alignment: .leading)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
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
            .padding(14)
            .frame(maxWidth: 680, alignment: .leading)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine)
        }
    }

    private var stepList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("步骤")
                .font(.headline)
            VStack(alignment: .leading, spacing: 7) {
                ForEach(stepRows, id: \.title) { row in
                    Label(row.title, systemImage: row.systemImage)
                        .font(.callout)
                        .foregroundStyle(row.tint)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var warningSection: some View {
        if let progressWarning {
            Label(progressWarning, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.orange)
                .frame(maxWidth: 680, alignment: .leading)
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
            .frame(maxWidth: 680, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if isCancellationRequested {
                ProgressView()
                    .controlSize(.small)
                Text("正在暂停...")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Button("Cancel", action: onCancel)
                .disabled(isCancellationRequested)
        }
        .frame(maxWidth: 680)
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

struct InitDoneStepView: View {
    let result: RepositoryInitializationResult
    let errorMapping: CoreErrorMappingSnapshot?
    let onOpenRepository: () -> Void
    let onOpenInFinder: () async -> Void

    @State private var isOpeningFinder = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            pathBox
            summarySection
            openErrorSection
            footer
        }
        .padding(.horizontal, 72)
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("资料库已准备好", systemImage: "checkmark.circle.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.green)
                .accessibilityAddTraits(.isHeader)
            Text("AreaMatrix 已完成初始化。你现在可以浏览资料库，" +
                "或把文件拖进窗口开始归档。")
                .font(.title3)
                .frame(maxWidth: 720, alignment: .leading)
        }
    }

    private var pathBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("资料库路径")
                .font(.headline)
            Text(result.repoPath)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(3)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: 720, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("完成摘要")
                .font(.headline)
            ForEach(summaryItems, id: \.self) { item in
                Label(item, systemImage: "checkmark")
                    .font(.callout)
            }
        }
        .frame(maxWidth: 720, alignment: .leading)
    }

    @ViewBuilder
    private var openErrorSection: some View {
        if let errorMapping {
            VStack(alignment: .leading, spacing: 8) {
                Label("无法打开资料库", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                Text(errorMapping.userMessage)
                Text(errorMapping.suggestedAction)
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(14)
            .frame(maxWidth: 720, alignment: .leading)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Open in Finder") {
                Task {
                    await openInFinder()
                }
            }
            .disabled(isOpeningFinder)

            if isOpeningFinder {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()
            Button(errorMapping == nil ? "Open Repository" : "Retry Open Repository", action: onOpenRepository)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: 720)
    }

    @MainActor
    private func openInFinder() async {
        guard !isOpeningFinder else { return }

        isOpeningFinder = true
        defer {
            isOpeningFinder = false
        }
        await onOpenInFinder()
    }

    private var summaryItems: [String] {
        switch result.mode {
        case .createEmpty:
            ["已创建默认分类", "已创建本地索引", "已启用自动概览"]
        case .adoptExisting:
            [
                "已建立本地索引",
                "已扫描现有文件",
                "已保留原有目录结构",
                "已生成内部概览"
            ]
        }
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
