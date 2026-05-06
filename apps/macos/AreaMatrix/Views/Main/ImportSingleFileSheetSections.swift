import SwiftUI

struct ImportSingleFileStorageModeSection: View {
    @Binding var selectedMode: ImportSingleFileStorageMode

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("存储模式", selection: $selectedMode) {
                ForEach(ImportSingleFileStorageMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)
            Text(selectedMode.explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

struct ImportSingleFileImportStatusSection: View {
    let status: ImportSingleFileImportStatus
    let disabledReason: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if status.isImporting {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(status.message ?? "正在导入...")
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
