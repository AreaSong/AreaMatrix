import SwiftUI

struct ReplaceConfirmSheet: View {
    let context: SingleFileReplaceConfirmationContext
    var errorMessage: String?
    var diagnosticsMessage: String?
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onCollectDiagnostics: () -> Void
    let onConfirm: (SingleFileReplaceConfirmationDecision) -> Void

    @State private var understandsReplace = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("确认替换？")
                .font(.title2.weight(.semibold))
            Text("你将用新文件替换资料库中的已有文件。")
                .font(.callout)

            replaceSummary
            impactSummary
            if errorMessage != nil {
                recoveryActions
            } else {
                Toggle("我理解这是替换操作", isOn: $understandsReplace)
                actions
            }
        }
        .padding(24)
        .frame(minWidth: 460)
        .accessibilityElement(children: .contain)
    }

    private var replaceSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            fileSummary(title: "将被替换", path: context.existingPath,
                        sizeBytes: context.existingSizeBytes, modifiedAt: context.existingModifiedAt)
            Divider()
            fileSummary(title: "替换为", path: context.incomingPath,
                        sizeBytes: context.incomingSizeBytes, modifiedAt: context.incomingModifiedAt)
            LabeledContent("目标位置", value: context.targetRelativePath)
        }
    }

    private var impactSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("旧文件将移到系统废纸篓。")
            Text("新文件将写入原目标位置。")
            Text("这次操作会记录到改动日志。")
            Text("如果导入失败，AreaMatrix 会保持原文件不变或恢复到安全状态。")
            if !context.isTrashAvailable {
                Text("Replace requires system Trash")
                    .foregroundStyle(.orange)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private var recoveryActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            if let diagnosticsMessage {
                Text(diagnosticsMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Diagnostics do not include user file contents.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Collect Diagnostics...", action: onCollectDiagnostics)
                Button("Retry", action: onRetry)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var actions: some View {
        HStack {
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button("Replace", role: .destructive) {
                onConfirm(context.decision(understandsReplace: understandsReplace))
            }
            .keyboardShortcut(.defaultAction)
            .disabled(isReplaceDisabled)
            .help(replaceDisabledReason ?? "确认替换选择；实际导入仍在来源 ImportSheet 中执行")
        }
    }

    private var isReplaceDisabled: Bool {
        replaceDisabledReason != nil
    }

    private var replaceDisabledReason: String? {
        if !understandsReplace {
            return "请先勾选我理解这是替换操作"
        }
        if !context.isTrashAvailable {
            return "Replace requires system Trash"
        }
        return nil
    }

    private func fileSummary(
        title: String,
        path: String,
        sizeBytes: Int64?,
        modifiedAt: Int64?
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title, value: path)
            if let sizeBytes {
                LabeledContent("大小", value: ByteCountFormatter.string(
                    fromByteCount: sizeBytes,
                    countStyle: .file
                ))
            }
            if let modifiedAt {
                LabeledContent("修改时间", value: DateFormatter.localizedString(
                    from: Date(timeIntervalSince1970: TimeInterval(modifiedAt)),
                    dateStyle: .medium,
                    timeStyle: .short
                ))
            }
        }
        .font(.callout)
    }
}
