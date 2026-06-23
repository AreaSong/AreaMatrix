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
        VStack(alignment: .center, spacing: 28) {
            header

            VStack(spacing: 20) {
                errorSummary
                recoveryAdvice
                diagnosticsSection
            }
            .frame(maxWidth: 440)

            footer
        }
        .areaMatrixOnboardingPanel()
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
        VStack(alignment: .center, spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.orange)
                .padding(.bottom, 8)

            Text("初始化未完成")
                .font(.system(size: 32, weight: .semibold))
                .accessibilityAddTraits(.isHeader)

            Text("AreaMatrix 没能完成资料库初始化。\n你的原始文件没有被移动、重命名、删除或覆盖。")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
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
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.1), lineWidth: 1))
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
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.1), lineWidth: 1))
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
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.15), lineWidth: 1))
    }

    private var footer: some View {
        HStack {
            Button(action: onQuit) { Text("退出") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

            Spacer()

            Button("诊断报告...") {
                isDiagnosticsPrivacyPresented = true
            }
            .controlSize(.large)
            .disabled(isActionInFlight)

            Button("更改位置", action: onChangePath)
                .controlSize(.large)
                .disabled(isActionInFlight)

            Button("重试", action: onRetry)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canRetry || isActionInFlight)
        }
        .frame(maxWidth: 440)
        .padding(.top, 16)
    }

    private var isActionInFlight: Bool {
        if case .collecting = diagnostics {
            return true
        }
        return false
    }
}
