import SwiftUI

struct InitFailedStepView: View {
    let repoPath: String
    let mapping: CoreErrorMappingSnapshot?
    let diagnostics: InitializationDiagnosticsState
    let canRetry: Bool
    let onChangePath: () -> Void
    let onRetry: () -> Void
    let onCollectDiagnostics: () async -> Void
    let onQuit: () -> Void

    @State private var isDetailsExpanded = false
    @State private var isDiagnosticsPrivacyPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            errorSummary
            recoveryAdvice
            diagnosticsSection
            footer
        }
        .padding(.horizontal, 72)
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .confirmationDialog(
            "Collect diagnostics?",
            isPresented: $isDiagnosticsPrivacyPresented
        ) {
            Button("Collect Diagnostics...") {
                Task { await onCollectDiagnostics() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Diagnostics do not include user file contents, are not uploaded, " +
                "and paths and usernames are redacted before display.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("初始化未完成")
                .font(.system(size: 34, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text("AreaMatrix 没能完成资料库初始化。你的原始文件没有被移动、" +
                "重命名、删除或覆盖。")
                .font(.title3)
                .frame(maxWidth: 720, alignment: .leading)
        }
    }

    private var errorSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("错误摘要")
                .font(.headline)
            Text(mapping?.userMessage ?? "Unknown initialization error")
            Text("路径：\(repoPath)")
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
            Text("错误代码：\(mapping?.kind.rawValue ?? "Unknown")")
            Text("严重程度：\(mapping?.severity.rawValue ?? "Unknown")")
            DisclosureGroup("Show details", isExpanded: $isDetailsExpanded) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recoverability: \(mapping?.recoverability.rawValue ?? "Unknown")")
                    Text("Raw context: \(mapping?.rawContext ?? repoPath)")
                        .textSelection(.enabled)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(14)
        .frame(maxWidth: 720, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }

    private var recoveryAdvice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("恢复建议")
                .font(.headline)
            Text(mapping?.suggestedAction ??
                "请检查文件夹权限、释放磁盘空间，或选择其他资料库位置后重试。")
        }
        .font(.callout)
        .frame(maxWidth: 720, alignment: .leading)
    }

    @ViewBuilder
    private var diagnosticsSection: some View {
        switch diagnostics {
        case .idle, .confirmingPrivacy:
            EmptyView()
        case .collecting:
            Label("Preparing redacted diagnostics...", systemImage: "arrow.clockwise")
                .font(.callout)
                .foregroundStyle(.secondary)
        case let .collected(snapshot):
            collectedDiagnostics(snapshot)
        case let .failed(mapping):
            failedDiagnostics(mapping)
        }
    }

    private func collectedDiagnostics(_ snapshot: DiagnosticsSnapshotSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Diagnostics collected", systemImage: "doc.badge.gearshape")
                .font(.headline)
            Text(snapshot.snapshotPath)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
            ForEach(snapshot.warnings.prefix(3), id: \.self) { warning in
                Text(warning)
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
        .padding(14)
        .frame(maxWidth: 720, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }

    private func failedDiagnostics(_ mapping: CoreErrorMappingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Diagnostics could not be collected", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(mapping.userMessage)
            Text(mapping.suggestedAction)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(14)
        .frame(maxWidth: 720, alignment: .leading)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Change Path", action: onChangePath)
                .disabled(isActionInFlight)
            Button("Collect Diagnostics...") {
                isDiagnosticsPrivacyPresented = true
            }
            .disabled(isActionInFlight)
            Spacer()
            Button("Retry", action: onRetry)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canRetry || isActionInFlight)
            Button("Quit", role: .destructive, action: onQuit)
        }
        .frame(maxWidth: 720)
    }

    private var isActionInFlight: Bool {
        if case .collecting = diagnostics {
            return true
        }
        return false
    }
}
