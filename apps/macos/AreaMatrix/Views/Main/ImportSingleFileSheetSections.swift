import SwiftUI

struct ImportCopyStorageModeSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("存储模式", selection: .constant("Copy")) {
                Text("Copy").tag("Copy")
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)
            Text("保留原文件，复制到 AreaMatrix 资料库。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

struct ImportCopyStatusSection: View {
    let status: ImportSingleFileImportStatus
    let disabledReason: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if status.isImporting {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(status.message ?? "正在复制导入...")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            } else if let message = status.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(statusStyle)
            }

            if let disabledReason {
                Text(disabledReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var statusStyle: Color {
        switch status {
        case .failed, .blocked:
            return .red
        case .imported:
            return .green
        case .idle, .importing:
            return .secondary
        }
    }
}
