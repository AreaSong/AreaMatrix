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

struct ValidatePathStepView: View {
    let pathText: String
    let validation: RepoPathValidationSnapshot?
    let latestScanSession: ScanSessionSnapshot?
    let errorMessage: String?
    let errorMapping: CoreErrorMappingSnapshot?
    let isValidating: Bool
    let isICloudRiskAccepted: Bool
    let canContinue: Bool
    let primaryActionTitle: String
    let onBack: () -> Void
    let onChangePath: () -> Void
    let onRetry: () -> Void
    let onICloudRiskAcceptedChanged: (Bool) -> Void
    let onContinue: () -> Void

    private var displayedPath: String {
        validation?.repoPath ?? pathText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            pathSummary
            checkList
            notices
            footer
        }
        .padding(.horizontal, 72)
        .padding(.vertical, 42)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("校验资料库路径")
                .font(.system(size: 34, weight: .semibold, design: .default))
                .accessibilityAddTraits(.isHeader)
            Text("AreaMatrix 会先检查路径状态，再进入初始化或打开流程。")
                .font(.title3)
                .frame(maxWidth: 620, alignment: .leading)
        }
    }

    private var pathSummary: some View {
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

    private var checkList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("检查列表")
                .font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(checkRows, id: \.title) { row in
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
            .padding(14)
            .frame(maxWidth: 620, alignment: .leading)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var notices: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isValidating {
                ProgressView("正在检查路径...")
            }
            if let errorMapping {
                errorMappingNotice(errorMapping)
            } else if let errorMessage {
                notice("路径不可用", "exclamationmark.triangle", .red, [errorMessage])
            }
            if validation?.isInitialized == true {
                notice("已找到 AreaMatrix 资料库", "externaldrive.connected.to.line.below", .green, [
                    "该文件夹已经包含 AreaMatrix 元数据。",
                    "AreaMatrix 将打开现有资料库，不会重新初始化或接管。",
                    "Repo path: \(displayedPath)",
                ])
            }
            if shouldShowAdoptExistingNotice {
                notice("将接管已有目录", "folder.badge.gearshape", .orange, [
                    "将创建 .areamatrix/ 内部目录。",
                    "将扫描现有文件和文件夹。",
                    "不移动、不重命名、不删除、不覆盖任何已有文件。",
                    "已有 README.md 和项目目录结构保持原样。",
                ])
            }
            if validation?.isICloudPath == true {
                iCloudNotice
            }
            if let session = latestAdoptScanSession {
                scanSessionNotice(session)
            }
        }
    }

    private var shouldShowAdoptExistingNotice: Bool {
        validation?.recommendedMode == .adoptExisting ||
            validation?.issues.contains(.nonEmptyDirectory) == true
    }

    private var latestAdoptScanSession: ScanSessionSnapshot? {
        guard latestScanSession?.kind == .adopt else {
            return nil
        }

        return latestScanSession
    }

    private var iCloudNotice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("iCloud Drive 路径", systemImage: "icloud")
                .font(.headline)
                .foregroundStyle(.blue)
            Text("iCloud 同步可能带来延迟、占位内容与冲突风险。")
                .font(.callout)
                .foregroundStyle(.secondary)
            Toggle(
                "我理解 iCloud 同步可能带来延迟与冲突风险",
                isOn: Binding(get: { isICloudRiskAccepted }, set: onICloudRiskAcceptedChanged)
            )
        }
        .padding(14)
        .frame(maxWidth: 620, alignment: .leading)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func scanSessionNotice(_ session: ScanSessionSnapshot) -> some View {
        notice("发现未完成接管扫描", "arrow.clockwise.circle", .orange, [
            "状态：\(session.status.rawValue)。",
            "已索引 \(session.inserted) 个，更新 \(session.updated) 个，跳过 \(session.skipped) 个。",
            "最后位置：\(session.lastPath ?? "尚未记录")。",
        ])
    }

    private func errorMappingNotice(_ mapping: CoreErrorMappingSnapshot) -> some View {
        notice("路径不可用", "exclamationmark.triangle", mapping.severity.tint, [
            mapping.userMessage,
            "建议：\(mapping.suggestedAction)",
            "严重程度：\(mapping.severity.displayName)；恢复方式：\(mapping.recoverability.displayName)",
        ])
    }

    private var footer: some View {
        HStack {
            Button("Back", action: onBack)
            Button("Change Path", action: onChangePath)
            Spacer()
            Button("Retry", action: onRetry)
            Button(primaryActionTitle, action: onContinue)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canContinue)
        }
        .disabled(isValidating)
        .frame(maxWidth: 620)
    }

    private var checkRows: [(title: String, detail: String, status: ValidatePathCheckStatus)] {
        guard let validation else {
            return [
                ("路径存在且是文件夹", displayedPath, .checking),
                ("可读权限", "等待 Core 校验", .checking),
                ("可写权限", "等待 Core 校验", .checking),
                ("iCloud 路径", "等待 Core 校验", .checking),
                ("已有 AreaMatrix repo", "等待 Core 校验", .checking),
                ("非空目录", "等待 Core 校验", .checking),
            ]
        }

        let isUsableDirectory = validation.exists && validation.isDirectory
        let hasNonEmptyDirectory = validation.issues.contains(.nonEmptyDirectory)

        return [
            (
                "路径存在且是文件夹",
                isUsableDirectory ? "可作为候选目录" : "请选择已存在的文件夹",
                isUsableDirectory ? .passed : .failed
            ),
            ("可读权限", validation.isReadable ? "Passed" : "Failed", validation.isReadable ? .passed : .failed),
            ("可写权限", validation.isWritable ? "Passed" : "Failed", validation.isWritable ? .passed : .failed),
            (
                "iCloud 路径",
                validation.isICloudPath ? "Warning" : "Passed",
                validation.isICloudPath ? .warning : .passed
            ),
            (
                "已有 AreaMatrix repo",
                validation.isInitialized ? "Warning" : "Passed",
                validation.isInitialized ? .warning : .passed
            ),
            (
                "非空目录",
                hasNonEmptyDirectory ? "Warning" : "Passed",
                hasNonEmptyDirectory ? .warning : .passed
            ),
        ]
    }

    private func notice(_ title: String, _ image: String, _ tint: Color, _ lines: [String]) -> some View {
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

private enum ValidatePathCheckStatus {
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
