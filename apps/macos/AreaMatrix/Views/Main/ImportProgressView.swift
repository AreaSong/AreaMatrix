import SwiftUI

struct ImportProgressView: View {
    let state: ImportProgressRouteState
    let onReturnToRepository: () -> Void

    @State private var showsDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(state.toolbarText)
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text(state.titleText)
                    .font(.headline)
                Text(state.bannerText)
                Text("当前：\(state.currentPath)")
                    .textSelection(.enabled)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 8) {
                ForEach(state.items) { item in
                    ImportingListRow(item: item)
                }
            }
            .accessibilityElement(children: .contain)

            if showsDetails {
                VStack(alignment: .leading, spacing: 6) {
                    Text("资料库：\(state.repoPath)")
                        .textSelection(.enabled)
                    Text("已完成 \(state.completed)，失败 \(state.failed)，剩余 \(state.remaining)")
                    if state.skipped > 0 {
                        Text("跳过 \(state.skipped)")
                    }
                    if state.pending > 0 {
                        Text("待下载 \(state.pending)")
                    }
                    if let errorMapping = state.errorMapping {
                        Text("错误级别：\(errorMapping.severity.rawValue)")
                        Text("建议操作：\(errorMapping.suggestedAction)")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            HStack {
                Button(state.detailsButtonTitle) {
                    showsDetails.toggle()
                }
                if state.isFailed {
                    Button("Back to repository", action: onReturnToRepository)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
    }
}

private struct ImportingListRow: View {
    let item: ImportBatchProgressSnapshot.Item

    var body: some View {
        HStack(spacing: 10) {
            statusIcon
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.targetPath)
                    .lineLimit(1)
                if let errorMessage = item.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                } else if item.sourcePath != item.targetPath {
                    Text(item.sourcePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(item.phase.rawValue)
                .font(.caption.monospaced())
                .foregroundStyle(phaseColor)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.phase {
        case .copying:
            ProgressView()
                .controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        }
    }

    private var phaseColor: Color {
        switch item.phase {
        case .failed:
            return .red
        case .done:
            return .green
        case .copying, .pending:
            return .secondary
        }
    }
}
