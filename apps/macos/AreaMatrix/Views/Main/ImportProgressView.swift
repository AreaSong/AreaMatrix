import SwiftUI

struct ImportProgressView: View {
    let state: ImportProgressRouteState
    let onStopAfterCurrentFile: () -> Void
    let onViewDetails: () -> Void
    let onRetryCurrentItem: () -> Void
    let onStopAndViewResults: () -> Void
    let onRequestDiagnostics: () -> Void
    let onConfirmDiagnostics: () -> Void
    let onCancelDiagnostics: () -> Void
    let onOpenRepositoryInFinder: () -> Void

    @State private var isStopConfirmationPresented = false

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

            if state.isFailed {
                fatalErrorPanel
            }

            HStack {
                Button(state.detailsButtonTitle) {
                    onViewDetails()
                }
                if state.isRunning {
                    Button(stopButtonTitle) {
                        isStopConfirmationPresented = true
                    }
                    .disabled(state.stopState != .idle)
                }
            }
        }
        .padding(24)
        .alert("停止剩余导入？", isPresented: $isStopConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Stop", role: .destructive, action: onStopAfterCurrentFile)
        } message: {
            Text("已完成的文件会保留，未开始的文件会取消，当前文件会处理到安全点后停止。")
        }
        .alert("Collect Diagnostics?", isPresented: diagnosticsConfirmationBinding) {
            Button("Cancel", role: .cancel, action: onCancelDiagnostics)
            Button("Collect Diagnostics...", action: onConfirmDiagnostics)
        } message: {
            Text("Diagnostics do not include user file contents, are not uploaded, and paths/usernames are redacted.")
        }
    }

    private var fatalErrorPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("导入已暂停", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)
            Text("已完成 \(state.completed)，失败 \(state.failed)，未开始 \(state.remaining + state.pending)")
            Text("当前失败项：\(state.currentPath)")
                .textSelection(.enabled)
            if let errorMapping = state.errorMapping {
                Text("错误代码：\(errorMapping.kind.rawValue)")
                Text(errorMapping.suggestedAction)
                    .foregroundStyle(.secondary)
            }
            Text("已完成的文件会保留。未开始的文件不会自动导入。")
            Text("AreaMatrix 会先确认 staging 状态，再允许重试当前项。")
                .foregroundStyle(.secondary)
            Text(state.retryStatusText)
                .font(.caption)
                .foregroundStyle(state.canRetryCurrentItem ? .green : .secondary)
            diagnosticsStatus
            HStack {
                Button("Retry current item", action: onRetryCurrentItem)
                    .disabled(!state.canRetryCurrentItem)
                Button("Stop and view results", action: onStopAndViewResults)
                    .keyboardShortcut(.defaultAction)
                Button("Collect Diagnostics...", action: onRequestDiagnostics)
                    .disabled(diagnosticsIsCollecting)
                if state.isRepositoryFinderAvailable {
                    Button("Open repository in Finder", action: onOpenRepositoryInFinder)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var diagnosticsStatus: some View {
        switch state.diagnostics {
        case .idle, .confirmingPrivacy:
            EmptyView()
        case .collecting:
            Label("Collecting diagnostics...", systemImage: "doc.badge.gearshape")
                .font(.caption)
                .foregroundStyle(.secondary)
        case let .collected(snapshot):
            Label("Diagnostics collected: \(snapshot.snapshotPath)", systemImage: "doc.badge.gearshape")
                .font(.caption)
                .foregroundStyle(.secondary)
        case let .failed(mapping):
            Label("Diagnostics failed: \(mapping.userMessage)", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private var stopButtonTitle: String {
        switch state.stopState {
        case .idle:
            "Stop after current file"
        case .stopping:
            "Stopping..."
        case .stopped:
            "Stopped"
        }
    }

    private var diagnosticsIsCollecting: Bool {
        if case .collecting = state.diagnostics { return true }
        return false
    }

    private var diagnosticsConfirmationBinding: Binding<Bool> {
        Binding(
            get: {
                if case .confirmingPrivacy = state.diagnostics { return true }
                return false
            },
            set: { _ in }
        )
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
        case .copying, .hashing, .classifying:
            ProgressView()
                .controlSize(.small)
        case .moving:
            Image(systemName: "arrow.right.circle")
                .foregroundStyle(.orange)
        case .writingIndex:
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
            .red
        case .done:
            .green
        case .moving:
            .orange
        case .copying, .pending, .hashing, .classifying, .writingIndex:
            .secondary
        }
    }
}
