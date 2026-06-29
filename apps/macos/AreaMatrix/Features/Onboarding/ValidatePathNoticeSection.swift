import SwiftUI

enum ValidatePathNoticeRules {
    static func shouldShowAdoptExistingNotice(for validation: RepoPathValidationSnapshot?) -> Bool {
        guard let validation, !validation.isInitialized else {
            return false
        }

        return validation.recommendedMode == .adoptExisting ||
            validation.issues.contains(.nonEmptyDirectory)
    }
}

struct ValidatePathNotices: View {
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
                    "已有 README.md 和项目目录结构保持原样。"
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
                    "继续前请确认该卷会保持连接。"
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
            "Repo path: \(displayedPath)"
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
            "最后位置：\(session.lastPath ?? "尚未记录")。"
        ])
    }

    private func errorMappingNotice(_ mapping: CoreErrorMappingSnapshot) -> some View {
        ValidatePathNoticeCard(title: "路径不可用", image: "exclamationmark.triangle", tint: mapping.severity.tint, lines: [
            mapping.userMessage,
            "建议：\(mapping.suggestedAction)",
            "严重程度：\(mapping.severity.displayName)；恢复方式：\(mapping.recoverability.displayName)"
        ])
    }
}

private struct ValidatePathICloudNotice: View {
    let isAccepted: Bool
    let onAcceptedChanged: (Bool) -> Void

    var body: some View {
        TintedOutlinedStatusBanner(tint: .blue) {
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
        }
    }
}

private struct ValidatePathNoticeCard: View {
    let title: String
    let image: String
    let tint: Color
    let lines: [String]

    var body: some View {
        TintedOutlinedStatusBanner(tint: tint) {
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
        }
    }
}
