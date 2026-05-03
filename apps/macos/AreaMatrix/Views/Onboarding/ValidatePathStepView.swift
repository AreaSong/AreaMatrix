import SwiftUI

struct ValidatePathStepView: View {
    let pathText: String
    let validation: RepoPathValidationSnapshot?
    let existingRepositoryMetadata: ExistingRepositoryMetadataSnapshot?
    let latestScanSession: ScanSessionSnapshot?
    let errorMessage: String?
    let errorMapping: CoreErrorMappingSnapshot?
    let isValidating: Bool
    let isICloudRiskAccepted: Bool
    let canContinue: Bool
    let primaryActionTitle: String
    let showsCancel: Bool
    let onBack: () -> Void
    let onCancel: () -> Void
    let onChangePath: () -> Void
    let onRetry: () -> Void
    let onICloudRiskAcceptedChanged: (Bool) -> Void
    let onContinue: () -> Void

    private var displayedPath: String {
        validation?.repoPath ?? pathText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ValidatePathHeader()
            ValidatePathSummary(displayedPath: displayedPath)
            ValidatePathChecklist(displayedPath: displayedPath, validation: validation)
            ValidatePathNotices(
                displayedPath: displayedPath,
                validation: validation,
                existingRepositoryMetadata: existingRepositoryMetadata,
                latestScanSession: latestScanSession,
                errorMessage: errorMessage,
                errorMapping: errorMapping,
                isValidating: isValidating,
                isICloudRiskAccepted: isICloudRiskAccepted,
                onICloudRiskAcceptedChanged: onICloudRiskAcceptedChanged
            )
            ValidatePathFooter(
                isInitializedRepository: validation?.isInitialized == true,
                isValidating: isValidating,
                canContinue: canContinue,
                primaryActionTitle: primaryActionTitle,
                showsCancel: showsCancel,
                onBack: onBack,
                onCancel: onCancel,
                onChangePath: onChangePath,
                onRetry: onRetry,
                onContinue: onContinue
            )
        }
        .padding(.horizontal, 72)
        .padding(.vertical, 42)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

enum ValidatePathNoticeRules {
    static func shouldShowAdoptExistingNotice(for validation: RepoPathValidationSnapshot?) -> Bool {
        guard let validation, !validation.isInitialized else {
            return false
        }

        return validation.recommendedMode == .adoptExisting ||
            validation.issues.contains(.nonEmptyDirectory)
    }
}

private struct ValidatePathHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("校验资料库路径")
                .font(.system(size: 34, weight: .semibold, design: .default))
                .accessibilityAddTraits(.isHeader)
            Text("AreaMatrix 会先检查路径状态，再进入初始化或打开流程。")
                .font(.title3)
                .frame(maxWidth: 620, alignment: .leading)
        }
    }
}

private struct ValidatePathSummary: View {
    let displayedPath: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("当前路径")
                .font(.headline)
            Text(displayedPath)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(2)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: 620, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

private struct ValidatePathChecklist: View {
    let displayedPath: String
    let validation: RepoPathValidationSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("检查列表")
                .font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(rows, id: \.title) { row in
                    ValidatePathCheckRowView(row: row)
                }
            }
            .padding(14)
            .frame(maxWidth: 620, alignment: .leading)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var rows: [ValidatePathCheckRow] {
        guard let validation else {
            return [
                .init("路径存在且是文件夹", displayedPath, .checking),
                .init("可读权限", "等待 Core 校验", .checking),
                .init("可写权限", "等待 Core 校验", .checking),
                .init("可用空间", "等待容量检查", .checking),
                .init("iCloud 路径", "等待 Core 校验", .checking),
                .init("是否外置卷", "等待卷信息", .checking),
                .init("已有 AreaMatrix repo", "等待 Core 校验", .checking),
                .init("非空目录", "等待 Core 校验", .checking),
            ]
        }

        let isUsableDirectory = validation.exists && validation.isDirectory
        let hasNonEmptyDirectory = validation.issues.contains(.nonEmptyDirectory)

        return [
            .init(
                "路径存在且是文件夹",
                isUsableDirectory ? "可作为候选目录" : "请选择已存在的文件夹",
                isUsableDirectory ? .passed : .failed
            ),
            .init("可读权限", validation.isReadable ? "Passed" : "Failed", validation.isReadable ? .passed : .failed),
            .init("可写权限", validation.isWritable ? "Passed" : "Failed", validation.isWritable ? .passed : .failed),
            .init("可用空间", capacityDetail(for: validation), capacityStatus(for: validation)),
            .init(
                "iCloud 路径",
                validation.isICloudPath ? "Warning" : "Passed",
                validation.isICloudPath ? .warning : .passed
            ),
            .init("是否外置卷", externalVolumeDetail(for: validation), externalVolumeStatus(for: validation)),
            .init(
                "已有 AreaMatrix repo",
                validation.isInitialized ? "Warning" : "Passed",
                validation.isInitialized ? .warning : .passed
            ),
            .init("非空目录", hasNonEmptyDirectory ? "Warning" : "Passed", hasNonEmptyDirectory ? .warning : .passed),
        ]
    }

    private func capacityDetail(for validation: RepoPathValidationSnapshot) -> String {
        guard let bytes = validation.availableCapacityBytes else {
            return "检查结果缺失"
        }

        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func capacityStatus(for validation: RepoPathValidationSnapshot) -> ValidatePathCheckStatus {
        if validation.hasInsufficientAvailableCapacity {
            return .failed
        }

        return validation.availableCapacityBytes == nil ? .failed : .passed
    }

    private func externalVolumeDetail(for validation: RepoPathValidationSnapshot) -> String {
        switch validation.isExternalVolume {
        case .some(true): return "Warning"
        case .some(false): return "Passed"
        case nil: return "检查结果缺失"
        }
    }

    private func externalVolumeStatus(for validation: RepoPathValidationSnapshot) -> ValidatePathCheckStatus {
        switch validation.isExternalVolume {
        case .some(true): return .warning
        case .some(false): return .passed
        case nil: return .failed
        }
    }
}

private struct ValidatePathCheckRow: Equatable {
    let title: String
    let detail: String
    let status: ValidatePathCheckStatus

    init(_ title: String, _ detail: String, _ status: ValidatePathCheckStatus) {
        self.title = title
        self.detail = detail
        self.status = status
    }
}

private struct ValidatePathCheckRowView: View {
    let row: ValidatePathCheckRow

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.body.weight(.medium))
                Text("\(row.status.text): \(row.detail)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: row.status.systemImage)
                .foregroundStyle(row.status.tint)
        }
    }
}

private struct ValidatePathNotices: View {
    let displayedPath: String
    let validation: RepoPathValidationSnapshot?
    let existingRepositoryMetadata: ExistingRepositoryMetadataSnapshot?
    let latestScanSession: ScanSessionSnapshot?
    let errorMessage: String?
    let errorMapping: CoreErrorMappingSnapshot?
    let isValidating: Bool
    let isICloudRiskAccepted: Bool
    let onICloudRiskAcceptedChanged: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isValidating {
                ProgressView("正在检查路径...")
            }
            if let errorMapping {
                errorMappingNotice(errorMapping)
            } else if let errorMessage {
                ValidatePathNoticeCard(
                    title: "路径不可用",
                    image: "exclamationmark.triangle",
                    tint: .red,
                    lines: [errorMessage]
                )
            }
            if validation?.isInitialized == true {
                ValidatePathNoticeCard(
                    title: "已找到 AreaMatrix 资料库",
                    image: "externaldrive.connected.to.line.below",
                    tint: .green,
                    lines: existingRepoLines
                )
            }
            if ValidatePathNoticeRules.shouldShowAdoptExistingNotice(for: validation) {
                ValidatePathNoticeCard(title: "将接管已有目录", image: "folder.badge.gearshape", tint: .orange, lines: [
                    "将创建 .areamatrix/ 内部目录。",
                    "将扫描现有文件和文件夹。",
                    "不移动、不重命名、不删除、不覆盖任何已有文件。",
                    "已有 README.md 和项目目录结构保持原样。",
                ])
            }
            if validation?.isICloudPath == true {
                ValidatePathICloudNotice(
                    isAccepted: isICloudRiskAccepted,
                    onAcceptedChanged: onICloudRiskAcceptedChanged
                )
            }
            if validation?.isExternalVolume == true {
                ValidatePathNoticeCard(title: "外置卷路径", image: "externaldrive", tint: .orange, lines: [
                    "外置卷可能在断开连接后导致资料库不可用。",
                    "继续前请确认该卷会保持连接。",
                ])
            }
            if let session = latestAdoptScanSession {
                scanSessionNotice(session)
            }
        }
    }

    private var latestAdoptScanSession: ScanSessionSnapshot? {
        latestScanSession?.kind == .adopt ? latestScanSession : nil
    }

    private var existingRepoLines: [String] {
        [
            "该文件夹已经包含可打开的 .areamatrix/index.db。",
            "AreaMatrix 将打开现有资料库，不会重新初始化或接管。",
            schemaVersionLine,
            lastOpenedLine,
            "Repo path: \(displayedPath)",
        ]
    }

    private var schemaVersionLine: String {
        guard let version = existingRepositoryMetadata?.schemaVersion else {
            return "Schema version: reading metadata"
        }

        return "Schema version: v\(version)"
    }

    private var lastOpenedLine: String {
        guard let lastOpenedAt = existingRepositoryMetadata?.lastOpenedAt else {
            return "Last opened: Not recorded"
        }

        let date = Date(timeIntervalSince1970: TimeInterval(lastOpenedAt))
        return "Last opened: \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    private func scanSessionNotice(_ session: ScanSessionSnapshot) -> some View {
        ValidatePathNoticeCard(title: "发现未完成接管扫描", image: "arrow.clockwise.circle", tint: .orange, lines: [
            "状态：\(session.status.rawValue)。",
            "已索引 \(session.inserted) 个，更新 \(session.updated) 个，跳过 \(session.skipped) 个。",
            "最后位置：\(session.lastPath ?? "尚未记录")。",
        ])
    }

    private func errorMappingNotice(_ mapping: CoreErrorMappingSnapshot) -> some View {
        ValidatePathNoticeCard(title: "路径不可用", image: "exclamationmark.triangle", tint: mapping.severity.tint, lines: [
            mapping.userMessage,
            "建议：\(mapping.suggestedAction)",
            "严重程度：\(mapping.severity.displayName)；恢复方式：\(mapping.recoverability.displayName)",
        ])
    }
}

private struct ValidatePathICloudNotice: View {
    let isAccepted: Bool
    let onAcceptedChanged: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("iCloud Drive 路径", systemImage: "icloud")
                .font(.headline)
                .foregroundStyle(.blue)
            Text("iCloud 同步可能带来延迟、占位内容与冲突风险。")
                .font(.callout)
                .foregroundStyle(.secondary)
            Toggle(
                "我理解 iCloud 同步可能带来延迟与冲突风险",
                isOn: Binding(get: { isAccepted }, set: onAcceptedChanged)
            )
        }
        .padding(14)
        .frame(maxWidth: 620, alignment: .leading)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ValidatePathNoticeCard: View {
    let title: String
    let image: String
    let tint: Color
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: image)
                .font(.headline)
                .foregroundStyle(tint)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: 620, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ValidatePathFooter: View {
    let isInitializedRepository: Bool
    let isValidating: Bool
    let canContinue: Bool
    let primaryActionTitle: String
    let showsCancel: Bool
    let onBack: () -> Void
    let onCancel: () -> Void
    let onChangePath: () -> Void
    let onRetry: () -> Void
    let onContinue: () -> Void

    var body: some View {
        HStack {
            if isInitializedRepository {
                existingRepositoryFooter
            } else {
                defaultFooter
            }
        }
        .disabled(isValidating)
        .frame(maxWidth: 620)
    }

    @ViewBuilder
    private var defaultFooter: some View {
        Button("Back", action: onBack)
        if showsCancel {
            Button("Cancel", action: onCancel)
        }
        Button("Change Path", action: onChangePath)
        Spacer()
        Button("Retry", action: onRetry)
        primaryButton
    }

    private var existingRepositoryFooter: some View {
        Group {
            Button("Back", action: onBack)
            Spacer()
            Button("Choose another folder", action: onChangePath)
            primaryButton
        }
    }

    private var primaryButton: some View {
        Button(primaryActionTitle, action: onContinue)
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!canContinue)
    }
}

private extension CoreErrorSeveritySnapshot {
    var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .critical: return "Critical"
        }
    }

    var tint: Color {
        switch self {
        case .low: return .yellow
        case .medium: return .orange
        case .high: return .red
        case .critical: return .purple
        }
    }
}

private extension CoreErrorRecoverabilitySnapshot {
    var displayName: String {
        switch self {
        case .retryable: return "Retryable"
        case .userActionRequired: return "User action required"
        case .refreshRequired: return "Refresh required"
        case .fatal: return "Fatal"
        }
    }
}

private enum ValidatePathCheckStatus: Equatable {
    case checking
    case passed
    case warning
    case failed

    var text: String {
        switch self {
        case .checking: return "Checking"
        case .passed: return "Passed"
        case .warning: return "Warning"
        case .failed: return "Failed"
        }
    }

    var systemImage: String {
        switch self {
        case .checking: return "clock"
        case .passed: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .checking: return .secondary
        case .passed: return .green
        case .warning: return .orange
        case .failed: return .red
        }
    }
}
